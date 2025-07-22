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

internal import Synchronization
internal import DequeModule

#if canImport(Darwin)
import Dispatch
#endif

/// A task executor that is backed by a single dedicated thread with platform-optimized I/O event handling.
///
/// `PThreadExecutor` provides a high-performance, single-threaded execution environment for Swift Concurrency tasks.
/// It maintains thread affinity by ensuring all operations execute on a dedicated background thread, making it ideal for
/// actor executors and scenarios requiring ordered processing.
///
/// ## Usage
///
/// ```swift
/// // Create executor for actor isolation
/// actor DatabaseActor {
///     nonisolated let executor = PThreadExecutor(name: "DatabaseActor")
///     nonisolated var unownedExecutor: UnownedSerialExecutor {
///         executor.asUnownedSerialExecutor()
///     }
/// }
///
/// // Use with task executor preference
/// let executor = PThreadExecutor(name: "ProcessingThread")
/// await withTaskExecutorPreference(executor) {
///     // Work executes on dedicated thread
/// }
/// ```
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
public final class PThreadExecutor: TaskExecutor, SerialExecutor, @unchecked Sendable {
  #if canImport(Darwin)
  typealias Selector = KQueueSelector
  #elseif canImport(Glibc)
  typealias Selector = EpollSelector
  #else
  #error("Unsupported platform")
  #endif
  /// This is the state that is accessed from multiple threads; hence, it must be protected via a lock.
  struct MultiThreadedState: ~Copyable {
    /// Indicates if we are running and about to pop more jobs. If this is true then we don't have to wake the selector.
    var pendingJobPop = false
    /// This is the deque of enqueued jobs that we have to execute in the order they got enqueued.
    var jobs = Deque<UnownedJob>(minimumCapacity: 4096)
  }

  /// This is the state that is bound to this thread.
  struct ThreadBoundState: ~Copyable {
    /// The executor's thread.
    ///
    /// This is an implicit unwrap since we need to create the executor before the thread. We are ensuring
    /// it is actually set before anything happens
    fileprivate var thread: Thread!

    /// The executor's selector.
    var selector: Selector {
      get {
        assert(self.thread.isCurrent)
        return self._selector
      }
      set {
        assert(self.thread.isCurrent)
        self._selector = newValue
      }
    }

    /// The jobs that are next in line to be executed.
    var nextExecutedJobs: NonCopyableDeque {
      _read {
        assert(self.thread.isCurrent)
        yield self._nextExecutedJobs
      }
      _modify {
        assert(self.thread.isCurrent)
        yield &self._nextExecutedJobs
      }
    }

    /// This method can be called from off thread so we are not asserting here.
    func wakeupSelector() throws {
      try self._selector.wakeup()
    }

    /// The backing storage for the selector.
    ///
    /// This is an implicit unwrap since we need to create the executor before the selector. We are ensuring
    /// it is actually set before anything happens
    var _selector: Selector!

    /// The backing storage of the next executed jobs.
    var _nextExecutedJobs: NonCopyableDeque

    init(_nextExecutedJobs: consuming NonCopyableDeque) {
      self._nextExecutedJobs = _nextExecutedJobs
    }
  }

  /// This is the state that is accessed from multiple threads; hence, it is protected via a lock.
  ///
  /// - Note:In the future we could use an MPSC queue and atomics here.
  let _multiThreadedState = Mutex(MultiThreadedState())

  /// This is the state that is accessed from the thread backing the executor.
  private var _threadBoundState: ThreadBoundState

  /// Returns if we are currently running on the executor.
  private var onExecutor: Bool {
    return self._threadBoundState.thread.isCurrent
  }

  /// Creates a new `PThreadExecutor` with a named background thread.
  ///
  /// This initializer creates a new executor with a dedicated background thread. The executor immediately
  /// begins processing jobs after initialization completes. The background thread continues running until
  /// the executor is deallocated.
  ///
  /// - Parameter name: The name assigned to the executor's background thread. This name appears in debugging
  ///   tools and crash reports for easier identification.
  public convenience init(name: String) {
    self.init()

    let threadConditionVariable = ConditionVariable(Thread?.none)
    Thread.spawnAndRun(name: name) { thread in
      assert(Thread.current == thread)
      do {
        self._threadBoundState.thread = thread
        self._threadBoundState.selector = try! Selector()
        threadConditionVariable.signal { optionalThread in
          optionalThread = thread
        }
        try self.run()
      } catch {
        // We fatalError here because the only reasons this can be hit is if the underlying kqueue/epoll give us
        // errors that we cannot handle which is an unrecoverable error for us.
        fatalError("Unexpected error while running SelectableEventLoop: \(error).")
      }
    }
    threadConditionVariable.wait {
      $0 != nil
    } block: { _ in
    }
  }

  internal init() {
    var nextExecutedJobs = Deque<UnownedJob>()
    // We will process 4096 jobs per while loop.
    nextExecutedJobs.reserveCapacity(4096)
    self._threadBoundState = .init(
      _nextExecutedJobs: NonCopyableDeque(deque: nextExecutedJobs)
    )
  }

  deinit {
    precondition(
      self._multiThreadedState.withLock { !$0.jobs.isEmpty },
      "PThreadExecutor had left over jobs when deiniting."
    )
  }

  public func enqueue(_ job: UnownedJob) {
    if self.onExecutor {
      // We are in the executor so we can just enqueue the job and
      // it will get dequeued after the current run loop tick.
      self._multiThreadedState.withLock { state in
        state.jobs.append(job)
      }
    } else {
      let shouldWakeSelector = self._multiThreadedState.withLock { state in
        state.jobs.append(job)
        guard state.pendingJobPop else {
          // We have to wake the selector and we are going to store that we are about to do that.
          state.pendingJobPop = true
          return true
        }
        // There is already a next tick scheduled so we don't have to wake the selector.
        return false
      }

      // We only need to wake up the selector if we're not in the executor. If we're in the executor already, we're
      // we're running a job already which means that we'll check at least once more if there are other jobs to run.
      // While we had the lock we also checked whether the executor was _already_ going to be woken.
      // This saves us a syscall on hot loops.
      //
      // In the future we'll use an MPSC queue here and that will complicate things, so we may get some spurious wakeups,
      // but as long as we're using the big dumb lock we can make this optimization safely.
      if shouldWakeSelector {
        // Nothing we can do really if we fail to wake the selector
        try? self._threadBoundState.wakeupSelector()
      }
    }
  }

  public func isIsolatingCurrentContext() -> Bool? {
    return self.onExecutor
  }

  private func assertOnExecutor() {
    assert(self.onExecutor)
  }

  private func preconditionOnExecutor() {
    precondition(self.onExecutor)
  }

  /// Wake the `Selector` which means `Selector.whenReady(...)` will unblock.
  internal func _wakeupSelector() throws {
    try self._threadBoundState.selector.wakeup()
  }

  /// Start processing the jobs and handle any I/O.
  ///
  /// This method will continue running and blocking if needed.
  internal func run() throws {
    self.assertOnExecutor()

    // We need to ensure we process all jobs even if a job enqueued another job
    while true {
      self._multiThreadedState.withLock { state in
        if !state.jobs.isEmpty {
          // We got some jobs that we should execute. Let's copy them over so we can
          // give up the lock.
          while self._threadBoundState.nextExecutedJobs.deque.count < 4096 {
            guard let job = state.jobs.popFirst() else {
              break
            }

            self._threadBoundState.nextExecutedJobs.append(job)
          }
        }

        if self._threadBoundState.nextExecutedJobs.deque.isEmpty {
          // We got no jobs to execute so we will block and need to be woken up.
          state.pendingJobPop = false
        }
      }

      // Execute all the jobs that were submitted
      let didExecuteJobs = !self._threadBoundState.nextExecutedJobs.deque.isEmpty

      while let job = self._threadBoundState.nextExecutedJobs.popFirst() {
        #if canImport(Darwin)
        autoreleasepool {
          job.runSynchronously(on: self.asUnownedSerialExecutor())
        }
        #else
        job.runSynchronously(on: self.asUnownedSerialExecutor())
        #endif
      }

      if didExecuteJobs {
        // We executed some jobs that might have enqueued new jobs
        continue
      }

      try self._threadBoundState.selector.whenReady(
        strategy: .block
      )

      self._multiThreadedState.withLock { $0.pendingJobPop = true }
    }
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension PThreadExecutor: CustomStringConvertible {
  public var description: String {
    "PThreadExecutor(\(self._threadBoundState.thread.description))"
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
struct NonCopyableDeque: ~Copyable {
  var deque: Deque<UnownedJob> = []

  mutating func popFirst() -> UnownedJob? {
    self.deque.popFirst()
  }

  mutating func append(_ newElement: UnownedJob) {
    self.deque.append(newElement)
  }
}
