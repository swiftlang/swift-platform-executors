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
public final class PThreadExecutor: TaskExecutor, @unchecked Sendable {
  #if canImport(Darwin)
  typealias Selector = KQueueSelector
  #elseif canImport(Glibc)
  typealias Selector = EpollSelector
  #else
  #error("Unsupported platform")
  #endif
  /// This is the state that is accessed from multiple threads; hence, it must be protected via a lock.
  private struct MultiThreadedState: ~Copyable {
    /// Indicates if we are running and about to pop more jobs. If this is true then we don't have to wake the selector.
    var pendingJobPop = false
    /// Indicates if the executor should stop.
    var shouldStop = false
    /// This is the queue of enqueued jobs that we have to execute in the order they got enqueued.
    var jobs = NonCopyablePriorityQueue()
  }

  /// This is the state that is bound to this thread.
  struct ThreadBoundState: ~Copyable {
    /// The executor's thread.
    ///
    /// This is an implicit unwrap since we need to create the executor before the thread. We are ensuring
    /// it is actually set before anything happens
    fileprivate var thread: Thread?

    /// The executor's selector.
    var selector: Selector {
      assert(self.thread!.isCurrent)
      return self._selector
    }

    /// The jobs that are next in line to be executed.
    fileprivate var nextExecutedJobs: NonCopyablePriorityQueue {
      _read {
        assert(self.thread!.isCurrent)
        yield self._nextExecutedJobs
      }
      _modify {
        assert(self.thread!.isCurrent)
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
    let _selector = try! Selector()

    /// The backing storage of the next executed jobs.
    fileprivate var _nextExecutedJobs: NonCopyablePriorityQueue

    fileprivate init(_nextExecutedJobs: consuming NonCopyablePriorityQueue) {
      self._nextExecutedJobs = _nextExecutedJobs
    }
  }

  /// This is the state that is accessed from multiple threads; hence, it is protected via a lock.
  ///
  /// - Note:In the future we could use an MPSC queue and atomics here.
  private let _multiThreadedState = Mutex(MultiThreadedState())

  /// This is the state that is accessed from the thread backing the executor.
  private var _threadBoundState: ThreadBoundState

  /// The next sequence number of an enqueued jobs.
  private let sequenceNumber = Atomic<UInt64>(0)

  /// Returns the thread of the executor
  internal var thread: Thread? {
    self._threadBoundState.thread
  }

  /// Returns if we are currently running on the executor.
  private var onExecutor: Bool {
    return self._threadBoundState.thread?.isCurrent ?? false
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

    let conditionVariable = ConditionVariable(false)
    Thread.spawnAndRun(name: name) { thread in
      assert(Thread.current == thread)
      do {
        conditionVariable.signal { $0.toggle() }
        try self.run { job in
          job.runSynchronously(on: self.asUnownedTaskExecutor())
        }
      } catch {
        // We fatalError here because the only reasons this can be hit is if the underlying kqueue/epoll give us
        // errors that we cannot handle which is an unrecoverable error for us.
        fatalError("Unexpected error while running SelectableEventLoop: \(error).")
      }
    }
    conditionVariable.wait {
      $0
    } block: { _ in
    }
  }

  internal init() {
    self._threadBoundState = .init(
      _nextExecutedJobs: NonCopyablePriorityQueue()
    )
  }

  deinit {
    precondition(
      self._multiThreadedState.withLock { $0.jobs.queue.isEmpty },
      "PThreadExecutor had left over jobs when deiniting."
    )
  }

  public func enqueue(_ job: consuming ExecutorJob) {
    if #available(macOS 26.0, *) {
      job.sequenceNumber =
        self.sequenceNumber.wrappingAdd(
          1,
          ordering: .relaxed
        ).newValue
    }

    let unownedJob = UnownedJob(job)
    self.modifyMultiThreadedStateAndWakeUpIfNeeded { state in
      state.jobs.push(unownedJob)
    }
  }

  internal func stop() {
    self.modifyMultiThreadedStateAndWakeUpIfNeeded { state in
      state.shouldStop = true
    }
  }

  private func modifyMultiThreadedStateAndWakeUpIfNeeded(body: (inout MultiThreadedState) -> Void) {
    if self.onExecutor {
      // We are in the executor so we can just modify the state.
      self._multiThreadedState.withLock { state in
        body(&state)
      }
    } else {
      let shouldWakeSelector = self._multiThreadedState.withLock { state in
        body(&state)
        guard state.pendingJobPop else {
          // We have to wake the selector and we are going to store that we are about to do that.
          state.pendingJobPop = true
          return true
        }
        // There is already a next tick scheduled so we don't have to wake the selector.
        return false
      }

      // We only need to wake up the selector if we're not in the executor. If we're in the executor already,
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
  internal func run(runJobSynchronously: (UnownedJob) -> Void) throws {
    if self._threadBoundState.thread == nil {
      self._threadBoundState.thread = Thread.current
    }
    self.assertOnExecutor()

    // We need to ensure we process all jobs even if a job enqueued another job
    while true {
      let shouldStop = self._multiThreadedState.withLock { state in
        if state.shouldStop {
          state.shouldStop = false
          return true
        }
        if !state.jobs.queue.isEmpty {
          // We got some jobs that we should execute. Let's copy them over so we can
          // give up the lock.
          assert(self._threadBoundState.nextExecutedJobs.queue.isEmpty)
          swap(&state.jobs, &self._threadBoundState.nextExecutedJobs)
        }

        if self._threadBoundState.nextExecutedJobs.queue.isEmpty {
          // We got no jobs to execute so we will block and need to be woken up.
          state.pendingJobPop = false
        }
        return false
      }

      if shouldStop {
        // We need to stop now
        break
      }

      // Execute all the jobs that were submitted
      let didExecuteJobs = !self._threadBoundState.nextExecutedJobs.queue.isEmpty

      while let job = self._threadBoundState.nextExecutedJobs.pop() {
        runJobSynchronously(job)
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
    "PThreadExecutor(\(self._threadBoundState.thread?.description ?? "not running"))"
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
private struct NonCopyablePriorityQueue: ~Copyable {
  var queue: PriorityQueue<UnownedJob>

  init() {
    if #available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *) {
      self.queue = .init(compare: compareJobsByPriorityAndSequenceNumber)
    } else {
      self.queue = .init(compare: compareJobsByPriorityAndID)
    }
  }

  mutating func pop() -> UnownedJob? {
    self.queue.pop()
  }

  mutating func push(_ newElement: UnownedJob) {
    self.queue.push(newElement)
  }
}
