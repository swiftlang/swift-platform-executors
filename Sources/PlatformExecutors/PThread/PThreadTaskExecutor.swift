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

#if os(Linux) || os(Android) || os(FreeBSD) || canImport(Darwin)
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
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
public final class PThreadTaskExecutor: TaskExecutor {
  /// The executor's name.
  private let name: String
  /// The pool's executors.
  ///
  /// This is nonisolated(unsafe) and a var since we need to pass self to the individual threads which requires
  /// us to be fully initialized.
  private nonisolated(unsafe) var executors: [PThreadExecutor]!
  /// The current index for selecting the next executor to run on.
  private let index = Atomic<Int>(0)

  /// Creates a new `PThreadTaskExecutor` with the specified pool size and thread naming.
  ///
  /// This initializer creates a pool of `PThreadTaskExecutor` instances, each with its own dedicated thread.
  ///
  /// - Parameters:
  ///   - name: The base name for the executor pool. Each thread in the pool will be named `"<name>-<index>"`
  ///     where index starts from 0.
  ///   - poolSize: The number of `PThreadExecutor` instances to create in the pool. Must be greater than 0.
  ///   If `nil` is passed then the systems available core count will be used. Defaults to `nil`.
  ///   - taskExecutor: The task executor to use in-case this executor gets wrapped.
  internal init(
    name: String,
    poolSize: Int? = nil,
    taskExecutor: UnownedTaskExecutor?
  ) {
    let poolSize = poolSize ?? SystemCoreCount.coreCount
    self.name = "\(name)-size(\(poolSize))"
    precondition(poolSize > 0, "The pool size must be positive")
    var executors = [PThreadExecutor]()
    executors.reserveCapacity(poolSize)
    let taskExecutor = taskExecutor ?? self.asUnownedTaskExecutor()
    for i in 0..<poolSize {
      executors
        .append(
          PThreadExecutor(
            name: "\(name)-\(i)",
            serialExecutor: nil,
            taskExecutor: taskExecutor
          )
        )
    }
    self.executors = executors
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
  ///   - body: A closure that gets access to the pooled task executor for the duration of execution.
  /// - Returns: The value returned by the body closure.
  public nonisolated(nonsending) static func withExecutor<Return, Failure: Error>(
    name: String,
    poolSize: Int? = nil,
    body: (PThreadTaskExecutor) async throws(Failure) -> Return
  ) async throws(Failure) -> Return {
    do {
      return try await self._withExecutor(
        name: name,
        poolSize: poolSize,
        taskExecutor: nil,
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
    taskExecutor: UnownedTaskExecutor?,
    body: (PThreadTaskExecutor) async throws -> Return
  ) async rethrows -> Return {
    let executor = PThreadTaskExecutor(
      name: name,
      poolSize: poolSize,
      taskExecutor: taskExecutor
    )

    return try await asyncDo {
      try await body(executor)
    } finally: {
      for pThreadExecutor in executor.executors {
        pThreadExecutor.shutdown()
      }
    }
  }

  public func enqueue(_ job: consuming ExecutorJob) {
    self.next().enqueue(job)
  }

  private func next() -> PThreadExecutor {
    self.executors[abs(self.index.wrappingAdd(1, ordering: .relaxed).newValue % self.executors.count)]
  }
}

#if !canImport(Darwin)
extension PThreadTaskExecutor: SchedulingExecutor {
  public var asSchedulingExecutor: SchedulingExecutor? {
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

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension PThreadTaskExecutor: CustomStringConvertible {
  public var description: String {
    "PThreadPoolExecutor(\(self.name))"
  }
}
#endif
