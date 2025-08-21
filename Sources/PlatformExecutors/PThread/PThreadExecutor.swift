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
//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2024 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if os(Linux) || os(Android) || os(FreeBSD) || canImport(Darwin)
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
/// // Use with task executor preference
/// let executor = PThreadExecutor(name: "ProcessingThread")
/// await withTaskExecutorPreference(executor) {
///     // Work executes on dedicated thread
/// }
/// ```
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
package final class PThreadExecutor: TaskExecutor, @unchecked Sendable {
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
    /// The condition variable that gets signalled once the thread is stopped.
    var stopConditionVariable: ConditionVariable<Bool>? = nil
    /// This is the queue of enqueued jobs that we have to execute in the order they got enqueued.
    var jobs: NonCopyablePriorityQueue<UnownedJob> = {
      guard #available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *) else {
        return .init(compare: compareJobsByPriorityAndID)
      }
      return .init(compare: compareJobsByPriorityAndSequenceNumber)
    }()
    /// This is the queue of enqueued jobs for the continuous clock.
    var continuousClockJobs: NonCopyablePriorityQueue<(ContinuousClock.Instant, UnownedJob)> = {
      guard #available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *) else {
        return .init(compare: compareJobsByContinuousClockInstantAndPriorityAndID(lhs:rhs:))
      }
      return .init(compare: compareJobsByContinuousClockInstantAndPriorityAndSequenceNumber(lhs:rhs:))
    }()
    /// This is the queue of enqueued jobs for the suspending clock.
    var suspendingClockJobs: NonCopyablePriorityQueue<(SuspendingClock.Instant, UnownedJob)> = {
      guard #available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *) else {
        return .init(compare: compareJobsBySuspendingClockInstantAndPriorityAndID(lhs:rhs:))
      }
      return .init(compare: compareJobsBySuspendingClockInstantAndPriorityAndSequenceNumber(lhs:rhs:))
    }()
  }

  /// This is the state that is bound to this thread.
  struct ThreadBoundState: ~Copyable {
    /// The executor's thread.
    fileprivate var thread: Thread?
    /// Indicates if the executor took over the calling thread
    fileprivate var tookOverThread: Bool = false

    func isOnThread() -> Bool {
      if self.thread == nil {
      }
      return self.thread?.isCurrentFunc() ?? false
    }

    /// The executor's selector.
    var selector: Selector {
      _read {
        assert(self.isOnThread())
        yield self._selector
      }
      _modify {
        assert(self.isOnThread())
        yield &self._selector
      }
    }

    /// The jobs that are next in line to be executed.
    fileprivate var nextExecutedJobs: ContiguousArray<UnownedJob> {
      _read {
        assert(self.isOnThread())
        yield self._nextExecutedJobs
      }
      _modify {
        assert(self.isOnThread())
        yield &self._nextExecutedJobs
      }
    }

    /// This method can be called from off thread so we are not asserting here.
    mutating func wakeupSelector() throws {
      try self._selector.wakeup()
    }

    /// The backing storage for the selector.
    ///
    /// This is a force try since there really is no way to handle these errors and this should never fail.
    var _selector = try! Selector()

    /// The backing storage of the next executed jobs.
    fileprivate var _nextExecutedJobs: ContiguousArray<UnownedJob>

    fileprivate init(_nextExecutedJobs: consuming ContiguousArray<UnownedJob>) {
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

  /// The amount of jobs to process in a single executor tick.
  /// This is a static var since those optimize better
  private static var jobsBatchSize: Int {
    4096
  }

  internal var threadDescription: String {
    return self._threadBoundState.thread?.description ?? "not running"
  }

  /// Returns if we are currently running on the executor.
  private var onExecutor: Bool {
    return self._threadBoundState.thread?.isCurrent ?? false
  }

  /// Creates a new platform-native task executor.
  ///
  /// This method creates a task executor backed by a dedicated pthread and ensures proper
  /// thread lifecycle management. The executor's thread will be automatically stopped and
  /// joined when the body closure completes, ensuring no thread leaks.
  ///
  /// - Parameters:
  ///   - name: The name assigned to the executor's background thread.
  ///   - body: A closure that gets access to the task executor for the duration of execution.
  /// - Returns: The value returned by the body closure.
  package nonisolated(nonsending) static func withExecutor<Return, Failure: Error>(
    name: String,
    body: (PThreadExecutor) async throws(Failure) -> Return
  ) async throws(Failure) -> Return {
    do {
      return try await self._withExecutor(
        name: name,
        taskExecutor: nil,
        serialExecutor: nil,
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
    taskExecutor: UnownedTaskExecutor?,
    serialExecutor: UnownedSerialExecutor?,
    body: (PThreadExecutor) async throws -> Return
  ) async rethrows -> Return {
    let executor = PThreadExecutor(
      name: name,
      serialExecutor: serialExecutor,
      taskExecutor: taskExecutor
    )

    return try await asyncDo {
      try await body(executor)
    } finally: {
      executor.shutdown()
    }
  }

  internal convenience init(
    name: String,
    serialExecutor: UnownedSerialExecutor?,
    taskExecutor: UnownedTaskExecutor?
  ) {
    self.init()

    let conditionVariable = ConditionVariable(true)
    let thread = Thread.spawnAndRun(name: name) {
      do {
        // Block until we've set the thread in the thread bound state
        conditionVariable.wait {
          return !$0
        } block: {
          _ in
        }

        // Signal that we've started running
        conditionVariable.signal { $0.toggle() }

        // It is incredibly important that we pass the right task executor
        // to the run methods otherwise the Concurrency runtime will re-enqueue
        // the task over and over again. If this executor is part of a thread pool
        // then we must pass the pool as the executor.
        if let taskExecutor {
          try self.run { job in
            job.runSynchronously(on: taskExecutor)
          }
        } else if let serialExecutor {
          try self.run { job in
            job.runSynchronously(on: serialExecutor)
          }
        } else {
          try self.run { job in
            job.runSynchronously(on: self.asUnownedTaskExecutor())
          }
        }
      } catch {
        // We fatalError here because the only reasons this can be hit is if the underlying kqueue/epoll give us
        // errors that we cannot handle which is an unrecoverable error for us.
        fatalError("Unexpected error while running SelectableEventLoop: \(error).")
      }
    }

    self._threadBoundState.thread = consume thread

    // Signal that we've set the thread in the thread bound state
    conditionVariable.signal { $0.toggle() }

    // Block until we've started running
    conditionVariable.wait {
      $0
    } block: { _ in
    }
  }

  internal init() {
    self._threadBoundState = .init(
      _nextExecutedJobs: ContiguousArray()
    )
  }

  deinit {
    precondition(
      self._multiThreadedState.withLock { $0.jobs.queue.isEmpty },
      "PThreadExecutor had left over jobs when deiniting."
    )
  }

  package func enqueue(_ job: consuming ExecutorJob) {
    if #available(macOS 9999, *) {
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

  internal func stop() -> ConditionVariable<Bool> {
    let conditionVariable = ConditionVariable(false)
    self.modifyMultiThreadedStateAndWakeUpIfNeeded { state in
      state.stopConditionVariable = conditionVariable
    }
    return conditionVariable
  }

  internal func shutdown() {
    let stopConditionVariable = self.stop()
    stopConditionVariable.wait {
      $0
    } block: { _ in
    }
    guard let thread = self._threadBoundState.thread.take() else {
      fatalError("Executor already shutdown")
    }

    thread.join()
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

  package func isIsolatingCurrentContext() -> Bool? {
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
      self._threadBoundState.tookOverThread = true
    }
    self.assertOnExecutor()

    // This is the outer loop that we use to block on our selector
    // and check if we should stop
    var stopConditionVariable: ConditionVariable<Bool>? = nil
    defer {
      stopConditionVariable?.signal { $0.toggle() }
    }
    while true {
      var moreJobsQueued = false
      var nextContinuousClockDeadline: ContinuousClock.Instant?
      var nextSuspendingClockDeadline: SuspendingClock.Instant?

      // This is the inner loop that processes one tick at a time. It can run
      // multiple times without blocking on the selector if there are many jobs
      // to processes or jobs are enqueued during a tick.
      while true {
        (stopConditionVariable, moreJobsQueued, nextContinuousClockDeadline, nextSuspendingClockDeadline) = self
          ._multiThreadedState.withLock { state in
            // We were flagged to stop so we need to exit this loop
            if let stopConditionVariable = state.stopConditionVariable {
              state.stopConditionVariable = nil
              return (stopConditionVariable, false, nil, nil)
            }
            // We got some jobs that we should execute. Let's copy them over so we can
            // give up the lock.
            let (moreJobsQueued, nextContinuousClockDeadline, nextSuspendingClockDeadline) = Self._popJobsLocked(
              jobs: &state.jobs,
              continuousClockJobs: &state.continuousClockJobs,
              suspendingClockJobs: &state.suspendingClockJobs,
              jobsCopy: &self._threadBoundState.nextExecutedJobs,
              batchSize: Self.jobsBatchSize
            )

            if self._threadBoundState.nextExecutedJobs.isEmpty {
              // We got no jobs to execute so we will block and need to be woken up.
              assert(moreJobsQueued == false)
              state.pendingJobPop = false
            }
            return (nil, moreJobsQueued, nextContinuousClockDeadline, nextSuspendingClockDeadline)
          }

        if stopConditionVariable != nil {
          // We need to stop now and break out of the inner loop
          break
        }

        if self._threadBoundState.nextExecutedJobs.isEmpty {
          // There are no more jobs to execute so we have to block now
          break
        }

        for job in self._threadBoundState.nextExecutedJobs {
          runJobSynchronously(job)
        }

        // Remove all the just executed jobs but keep the capacity.
        self._threadBoundState.nextExecutedJobs.removeAll(keepingCapacity: true)
      }

      if stopConditionVariable != nil {
        // We need to stop now and need to break out of the outer loop
        break
      }

      let strategy = self.currentSelectorStrategy(
        moreJobsQueued: moreJobsQueued,
        nextContinuousClockDeadline: nextContinuousClockDeadline,
        nextSuspendingClockDeadline: nextSuspendingClockDeadline
      )

      // Let's wait on the selector until an event happens
      try self._threadBoundState.selector.whenReady(
        strategy: strategy
      )

      // Our selector unblocked and we are going to pop some jobs
      self._multiThreadedState.withLock {
        $0.pendingJobPop = true
      }
    }
  }

  private static func _popJobsLocked(
    jobs: inout NonCopyablePriorityQueue<UnownedJob>,
    continuousClockJobs: inout NonCopyablePriorityQueue<(ContinuousClock.Instant, UnownedJob)>,
    suspendingClockJobs: inout NonCopyablePriorityQueue<(SuspendingClock.Instant, UnownedJob)>,
    jobsCopy: inout ContiguousArray<UnownedJob>,
    batchSize: Int
  ) -> (Bool, ContinuousClock.Instant?, SuspendingClock.Instant?) {
    // We expect empty jobsCopy, to put a new batch of tasks into
    assert(jobsCopy.isEmpty)

    var moreJobsToConsider = !jobs.queue.isEmpty
    var moreContinuousClockJobsToConsider = !continuousClockJobs.queue.isEmpty
    var moreSuspendingClockJobsToConsider = !suspendingClockJobs.queue.isEmpty

    guard moreJobsToConsider || moreContinuousClockJobsToConsider || moreSuspendingClockJobsToConsider else {
      // There are no jobs to consider.
      return (false, nil, nil)
    }

    // We only fetch the time one time as this may be expensive and is generally good enough as if we miss anything we will just do a non-blocking select again anyway.
    let continuousClockNow = ContinuousClock.now
    let suspendingClockNow = SuspendingClock.now
    var nextContinuousClockDeadline: ContinuousClock.Instant?
    var nextSuspendingClockDeadline: SuspendingClock.Instant?

    while moreJobsToConsider || moreContinuousClockJobsToConsider || moreSuspendingClockJobsToConsider {
      // We pick one job per iteration of the loop.
      // This prevents one queue starving the other.
      if moreJobsToConsider, jobsCopy.count < batchSize, let job = jobs.pop() {
        jobsCopy.append(job)
      } else {
        moreJobsToConsider = false
      }

      if moreContinuousClockJobsToConsider, jobsCopy.count < batchSize, let job = continuousClockJobs.peek() {
        if continuousClockNow.duration(to: job.0) <= .nanoseconds(0) {
          _ = continuousClockJobs.pop()
          jobsCopy.append(job.1)
        } else {
          nextContinuousClockDeadline = job.0
          moreContinuousClockJobsToConsider = false
        }
      } else {
        moreContinuousClockJobsToConsider = false
      }

      if moreSuspendingClockJobsToConsider, jobsCopy.count < batchSize, let job = suspendingClockJobs.peek() {
        if suspendingClockNow.duration(to: job.0) <= .nanoseconds(0) {
          _ = suspendingClockJobs.pop()
          jobsCopy.append(job.1)
        } else {
          nextSuspendingClockDeadline = job.0
          moreSuspendingClockJobsToConsider = false
        }
      } else {
        moreSuspendingClockJobsToConsider = false
      }
    }

    return (!jobs.queue.isEmpty, nextContinuousClockDeadline, nextSuspendingClockDeadline)
  }

  private func currentSelectorStrategy(
    moreJobsQueued: Bool,
    nextContinuousClockDeadline: ContinuousClock.Instant?,
    nextSuspendingClockDeadline: SuspendingClock.Instant?,
  ) -> SelectorStrategy {
    guard !moreJobsQueued else {
      // There are more jobs queued without a deadline so we just need to select all events again
      return .now
    }

    let continuousClockNow = ContinuousClock.now
    let suspendingClockNow = SuspendingClock.now
    let nextContinuousClockReady = nextContinuousClockDeadline.flatMap { continuousClockNow.duration(to: $0) }
    let nextSuspendingClockReady = nextSuspendingClockDeadline.flatMap { suspendingClockNow.duration(to: $0) }

    switch (nextContinuousClockReady, nextSuspendingClockReady) {
    case (.some(let nextContinuousClockReady), .some(let nextSuspendingClockReady)):
      guard nextContinuousClockReady <= .nanoseconds(0) || nextSuspendingClockReady <= .nanoseconds(0) else {
        return .blockUntilTimeout(
          continuousClockInstant: nextContinuousClockDeadline,
          suspendingClockInstant: nextSuspendingClockDeadline
        )
      }
      // Something is ready to be processed just do a non-blocking select of events.
      return .now
    case (.some(let nextContinuousClockReady), .none):
      guard nextContinuousClockReady <= .nanoseconds(0) else {
        return .blockUntilTimeout(
          continuousClockInstant: nextContinuousClockDeadline,
          suspendingClockInstant: nextSuspendingClockDeadline
        )
      }
      // Something is ready to be processed just do a non-blocking select of events.
      return .now
    case (.none, .some(let nextSuspendingClockReady)):
      guard nextSuspendingClockReady <= .nanoseconds(0) else {
        return .blockUntilTimeout(
          continuousClockInstant: nextContinuousClockDeadline,
          suspendingClockInstant: nextSuspendingClockDeadline
        )
      }
      // Something is ready to be processed just do a non-blocking select of events.
      return .now
    case (.none, .none):
      // No jobs to handle so just block.
      return .block
    }
  }
}

#if !canImport(Darwin)
@available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
extension PThreadExecutor: SchedulingExecutor {
  package var asSchedulingExecutor: SchedulingExecutor? {
    return self
  }

  package func enqueue<C: Clock>(
    _ job: consuming ExecutorJob,
    at instant: C.Instant,
    tolerance: C.Duration?,
    clock: C
  ) {
    job.sequenceNumber =
      self.sequenceNumber.wrappingAdd(
        1,
        ordering: .relaxed
      ).newValue
    switch instant {
    case let instant as ContinuousClock.Instant:
      let unownedJob = UnownedJob(job)
      self.modifyMultiThreadedStateAndWakeUpIfNeeded { state in
        state.continuousClockJobs.push((instant, unownedJob))
      }
    case let instant as SuspendingClock.Instant:
      let unownedJob = UnownedJob(job)
      self.modifyMultiThreadedStateAndWakeUpIfNeeded { state in
        state.suspendingClockJobs.push((instant, unownedJob))
      }
    default:
      clock.enqueue(
        job,
        on: self,
        at: instant,
        tolerance: tolerance
      )
    }
  }
}
#endif

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension PThreadExecutor: CustomStringConvertible {
  package var description: String {
    "PThreadExecutor(\(self._threadBoundState.thread?.description ?? "not running"))"
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
private struct NonCopyablePriorityQueue<T>: ~Copyable {
  var queue: PriorityQueue<T>

  init(compare: @escaping (borrowing T, borrowing T) -> Bool) {
    self.queue = .init(compare: compare)
  }

  mutating func pop() -> T? {
    self.queue.pop()
  }

  func peek() -> T? {
    self.queue.peek()
  }

  mutating func push(_ newElement: T) {
    self.queue.push(newElement)
  }
}
#endif
