//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if os(Linux) || os(Android) || os(FreeBSD) || canImport(Darwin) || os(WASI)
@_spi(ExperimentalScheduling) @_spi(ConcurrencyExecutors) @_spi(ExperimentalCustomExecutors) import _Concurrency
internal import Synchronization

/// A task executor that distributes work across multiple `PThreadExecutor` instances.
///
/// `PThreadTaskExecutor` provides a multi-threaded execution environment by maintaining a pool of executor
/// instances and distributing jobs across them. This design enables parallel execution while leveraging the
/// optimized single-threaded executors as building blocks.
///
/// ## Usage
///
/// ```swift
/// // Create executor for parallel processing
/// let executor = PThreadTaskExecutor(name: "ProcessingPool", poolSize: 4)
///
/// await withTaskExecutorPreference(executor) {
///     // Jobs distributed across the pool
///     async let result1 = heavyComputation1()
///     async let result2 = heavyComputation2()
///     async let result3 = heavyComputation3()
///
///     return await [result1, result2, result3]
/// }
/// ```
#if ExperimentalIO
@available(anyAppleOS 27.0, *)
#else
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
#endif
public final class PThreadTaskExecutor: TaskExecutor {
  /// The executor's name.
  private let name: String
  /// The pool's executors.
  ///
  /// This is nonisolated(unsafe) and a var since we need to pass self to the individual threads which requires
  /// us to be fully initialized.
  internal nonisolated(unsafe) var executors: [PThreadExecutor]!
  /// The current index for selecting the next executor to run on.
  private let index = Atomic<Int>(0)
  #if ExperimentalIO
  /// The number of threads that perform the file operations of mechanisms that cannot wait for files.
  private let blockingPoolSize: Int
  /// The queue of the threads that run blocking file operations as an unmanaged reference, or zero while it
  /// doesn't exist. It is created the first time an operation needs it.
  ///
  /// We are using an atomic here with a pointer to the queue to avoid swift_once overhead.
  private let _blockingQueue = Atomic<UInt>(0)
  /// Serializes the creation of the queue that runs blocking file operations.
  private let _blockingQueueCreation = Mutex<Void>(())
  #endif
  #if ExperimentalIO && !os(WASI)
  /// Whether the I/O mechanism of the pool's executors performs file operations.
  internal let performsFileOperations: Bool
  #endif

  /// Creates a new `PThreadTaskExecutor` with the specified pool size and thread naming.
  ///
  /// This initializer creates a pool of `PThreadTaskExecutor` instances, each with its own dedicated thread.
  ///
  /// - Parameters:
  ///   - name: The base name for the executor pool. Each thread in the pool will be named `"<name>-<index>"`
  ///     where index starts from 0.
  ///   - poolSize: The number of `PThreadExecutor` instances to create in the pool. Must be greater than 0.
  ///   If `nil` is passed then the systems available core count will be used. Defaults to `nil`.
  ///   - stackSize: The stack size in bytes of each thread in the pool, or `nil` to use the platform's default
  ///     thread stack size. Must be greater than 0. The value is rounded up to a multiple of the page size and
  ///     to at least 128 KiB, or the platform's minimum thread stack size if larger.
  ///   - taskExecutor: The task executor to use in-case this executor gets wrapped.
  ///   - ioBackend: The mechanism that the threads of the pool wait for events and perform their I/O with.
  ///   - blockingPoolSize: The number of threads that perform file operations with blocking syscalls.
  ///     If `nil` is passed then the pool size will be used.
  internal init(
    name: String,
    poolSize: Int? = nil,
    stackSize: Int? = nil,
    taskExecutor: UnownedTaskExecutor?,
    ioBackend: PThreadIOBackend = .platformDefault,
    blockingPoolSize: Int? = nil
  ) {
    let poolSize = poolSize ?? SystemCoreCount.coreCount
    self.name = "\(name)-size(\(poolSize))"
    precondition(poolSize > 0, "The pool size must be positive")
    // The default is evaluated once, so that all the executors use the same mechanism.
    let ioBackend = ioBackend.resolvingPlatformDefault()
    #if ExperimentalIO && !os(WASI)
    self.performsFileOperations = ioBackend.performsFileOperations
    #endif
    #if ExperimentalIO
    self.blockingPoolSize = blockingPoolSize ?? poolSize
    precondition(self.blockingPoolSize > 0, "The blocking pool size must be positive")
    #endif
    var executors = [PThreadExecutor]()
    executors.reserveCapacity(poolSize)
    let taskExecutor = unsafe taskExecutor ?? self.asUnownedTaskExecutor()
    for i in 0..<poolSize {
      unsafe executors
        .append(
          PThreadExecutor(
            name: "\(name)-\(i)",
            stackSize: stackSize,
            poolIndex: i,
            serialExecutor: nil,
            taskExecutor: unsafe taskExecutor,
            ioBackend: ioBackend
          )
        )
    }
    unsafe self.executors = executors
  }

  /// Creates a new platform-native pooled task executor.
  ///
  /// This method creates a pool of executors backed by dedicated pthreads and ensures proper
  /// thread lifecycle management. All executor threads will be automatically stopped and
  /// joined when the body closure completes, ensuring no thread leaks.
  ///
  /// - Parameters:
  ///   - name: The base name for the executor pool. Each thread will be named `"<name>-<index>"`.
  ///   - poolSize: The number of executors in the pool. Must be greater than 0.
  ///     If `nil` is passed then the systems available core count will be used. Defaults to `nil`.
  ///   - stackSize: The stack size in bytes of each thread in the pool, or `nil` to use the platform's default
  ///     thread stack size. Must be greater than 0. The value is rounded up to a multiple of the page size and
  ///     to at least 128 KiB, or the platform's minimum thread stack size if larger.
  ///   - ioBackend: The mechanism that the threads of the pool wait for events and perform their I/O with.
  ///   - blockingPoolSize: The number of threads that perform file operations with blocking syscalls.
  ///     If `nil` is passed then the pool size will be used.
  ///   - body: A closure that gets access to the pooled task executor for the duration of execution.
  /// - Returns: The value returned by the body closure.
  public nonisolated(nonsending) static func withExecutor<Return, Failure: Error>(
    name: String,
    poolSize: Int? = nil,
    stackSize: Int? = nil,
    ioBackend: PThreadIOBackend = .platformDefault,
    blockingPoolSize: Int? = nil,
    body: (PThreadTaskExecutor) async throws(Failure) -> Return
  ) async throws(Failure) -> Return {
    do {
      return try await unsafe self._withExecutor(
        name: name,
        poolSize: poolSize,
        stackSize: stackSize,
        taskExecutor: nil,
        ioBackend: ioBackend,
        blockingPoolSize: blockingPoolSize,
        body: body
      )
    } catch {
      throw error as! Failure
    }
  }

  // For some reason using typed throws here trips over the compiler
  // and it is not able to reason that the thrown error inside asyncDo is a Failure
  internal nonisolated(nonsending) static func _withExecutor<Return>(
    name: String,
    poolSize: Int? = nil,
    stackSize: Int? = nil,
    taskExecutor: UnownedTaskExecutor?,
    ioBackend: PThreadIOBackend = .platformDefault,
    blockingPoolSize: Int? = nil,
    body: (PThreadTaskExecutor) async throws -> Return
  ) async rethrows -> Return {
    let executor = unsafe PThreadTaskExecutor(
      name: name,
      poolSize: poolSize,
      stackSize: stackSize,
      taskExecutor: taskExecutor,
      ioBackend: ioBackend,
      blockingPoolSize: blockingPoolSize
    )

    return try await asyncDo {
      try await body(executor)
    } finally: {
      executor.shutdownThreads()
    }
  }

  /// Stops and joins the threads of the pool.
  internal func shutdownThreads() {
    #if ExperimentalIO
    let blockingQueue = self._blockingQueue.exchange(0, ordering: .acquiring)
    if let pointer = unsafe UnsafeRawPointer(bitPattern: blockingQueue) {
      unsafe Unmanaged<BlockingWorkQueue>.fromOpaque(pointer).takeRetainedValue().shutdown()
    }
    #endif
    for pThreadExecutor in unsafe self.executors {
      pThreadExecutor.shutdown()
    }
  }

  #if ExperimentalIO
  /// Returns the queue of the threads that run blocking file operations, creating it if it does not exist yet.
  internal func blockingQueue() -> BlockingWorkQueue {
    if let queue = self.existingBlockingQueue() {
      return queue
    }
    return self._blockingQueueCreation.withLock { _ in
      if let queue = self.existingBlockingQueue() {
        return queue
      }
      let queue = BlockingWorkQueue(
        name: "\(self.name)-blocking",
        threadCount: self.blockingPoolSize
      )
      // The atomic owns one reference to the queue until the threads are shut down.
      let pointer = unsafe Unmanaged.passRetained(queue).toOpaque()
      self._blockingQueue.store(UInt(bitPattern: pointer), ordering: .releasing)
      return queue
    }
  }

  private func existingBlockingQueue() -> BlockingWorkQueue? {
    let queue = self._blockingQueue.load(ordering: .acquiring)
    guard let pointer = unsafe UnsafeRawPointer(bitPattern: queue) else {
      return nil
    }
    return unsafe Unmanaged<BlockingWorkQueue>.fromOpaque(pointer).takeUnretainedValue()
  }
  #endif

  public func enqueue(_ job: consuming ExecutorJob) {
    self.next().enqueue(job)
  }

  internal func next() -> PThreadExecutor {
    unsafe self.executors[abs(self.index.wrappingAdd(1, ordering: .relaxed).newValue % self.executors.count)]
  }

  /// Returns the executor of the pool that the calling thread runs, or the next
  /// one if the calling thread is not one of the pool.
  internal func current() -> PThreadExecutor {
    if let pointer = unsafe PThread.currentExecutor {
      // The thread runs an executor, which is not necessarily one of this pool.
      let executor = unsafe Unmanaged<PThreadExecutor>.fromOpaque(pointer)
      let index = unsafe executor._withUnsafeGuaranteedRef { $0.poolIndex }
      if unsafe index < self.executors.count,
        unsafe UnsafeRawPointer(Unmanaged.passUnretained(self.executors[index]).toOpaque()) == pointer
      {
        return unsafe self.executors[index]
      }
    }
    return self.next()
  }
}

#if !canImport(Darwin)
@_spi(ExperimentalScheduling) extension PThreadTaskExecutor: SchedulingExecutor {
  @_spi(ExperimentalScheduling) public var asSchedulingExecutor: (any SchedulingExecutor)? {
    return self
  }

  public func enqueue<C: Clock>(
    _ job: consuming ExecutorJob,
    at instant: C.Instant,
    tolerance: C.Duration?,
    clock: C
  ) {
    self.next().enqueue(job, at: instant, tolerance: tolerance, clock: clock)
  }
}
#endif

#if ExperimentalIO
@available(anyAppleOS 27.0, *)
#else
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
#endif
extension PThreadTaskExecutor: CustomStringConvertible {
  public var description: String {
    "PThreadPoolExecutor(\(self.name))"
  }
}
#endif
