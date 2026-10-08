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

#if os(Linux) || os(Android) || os(FreeBSD) || canImport(Darwin) || os(WASI)
@_spi(ExperimentalScheduling) @_spi(ConcurrencyExecutors) @_spi(ExperimentalCustomExecutors) import _Concurrency
internal import Synchronization

#if canImport(Darwin)
import Dispatch
#endif

#if ExperimentalIO && !os(WASI)
internal import BasicContainers
internal import DequeModule

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
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
#if ExperimentalIO
// The I/O layer keeps continuations in the executor, which need a newer OS.
@available(anyAppleOS 27.0, *)
#else
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
#endif
package final class PThreadExecutor: TaskExecutor, @unchecked Sendable {
  /// The mechanism that performs this executor's I/O.
  typealias Backend = PlatformIOBackend
  /// This is the state that is accessed from multiple threads; hence, it must be protected via a lock.
  private struct MultiThreadedState: ~Copyable {
    /// Indicates if we are running and about to pop more jobs. If this is true then we don't have to wake the selector.
    var pendingJobPop = false
    /// The condition variable that gets signalled once the thread is stopped.
    var stopConditionVariable: ConditionVariable<Bool>? = nil
    #if ExperimentalIO && !os(WASI)
    /// The I/O work that other threads handed to the executor's thread.
    var submittedIOCommands = UniqueDeque<SubmittedIOCommand>()
    #endif
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
    /// The backing storage for the backend.
    ///
    /// This is a force try since there really is no way to handle these errors and this should never fail.
    var _backend = try! Backend()

    /// The backing storage of the next executed jobs.
    fileprivate var _nextExecutedJobs: ContiguousArray<UnownedJob>

    #if ExperimentalIO && !os(WASI)
    /// The backing storage of the next submitted I/O commands.
    fileprivate var _nextSubmittedIOCommands = UniqueDeque<SubmittedIOCommand>()

    /// The backing storage of the in-flight I/O operations.
    fileprivate var _inFlightIOOperations = UniqueDictionary<IOOperationID, Resumption>()
    #endif

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

  /// The executor's I/O mechanism.
  ///
  /// - Note: This may only be used on the executor's thread.
  internal var _backend: Backend {
    _read {
      assert(self.onExecutor)
      yield self._threadBoundState._backend
    }
    _modify {
      assert(self.onExecutor)
      yield &self._threadBoundState._backend
    }
  }

  /// The jobs that are next in line to be executed.
  private var nextExecutedJobs: ContiguousArray<UnownedJob> {
    _read {
      assert(self.onExecutor)
      yield self._threadBoundState._nextExecutedJobs
    }
    _modify {
      assert(self.onExecutor)
      yield &self._threadBoundState._nextExecutedJobs
    }
  }

  #if ExperimentalIO && !os(WASI)
  /// The I/O commands that are next in line to be applied.
  private var nextSubmittedIOCommands: UniqueDeque<SubmittedIOCommand> {
    _read {
      assert(self.onExecutor)
      yield self._threadBoundState._nextSubmittedIOCommands
    }
    _modify {
      assert(self.onExecutor)
      yield &self._threadBoundState._nextSubmittedIOCommands
    }
  }

  /// The currently inflight I/O operations.
  private var inFlightIOOperations: UniqueDictionary<IOOperationID, Resumption> {
    _read {
      assert(self.onExecutor)
      yield self._threadBoundState._inFlightIOOperations
    }
    _modify {
      assert(self.onExecutor)
      yield &self._threadBoundState._inFlightIOOperations
    }
  }
  #endif

  /// The next sequence number of an enqueued jobs.
  private let sequenceNumber = Atomic<UInt64>(0)

  /// The thread that runs this executor.
  private var thread: Thread?

  /// The handle that wakes the backend up from another thread.
  ///
  /// This is held separately so waking the executor up never touches its thread bound state.
  private let wakeupHandle: Backend.WakeupHandle

  #if ExperimentalIO && !os(WASI)
  /// The identity of the next submitted operation.
  ///
  /// This starts at one since zero is the identity of ``completedRegistration``.
  private let _nextOperationID = Atomic<UInt>(1)
  #endif

  #if ExperimentalIO
  /// The results of the operations that the backend handed over in this tick.
  ///
  /// - Note: This may only be used on the executor's thread.
  private var _completions: [(IOOperationID, Result<Int, IOError>)] = []
  #endif

  /// The amount of jobs to process in a single executor tick.
  /// This is a static var since those optimize better
  private static var jobsBatchSize: Int {
    4096
  }

  internal var threadDescription: String {
    return self.thread?.description ?? "not running"
  }

  /// The index of this executor in the pool of a ``PThreadTaskExecutor``, or zero if it is not part of a pool.
  internal let poolIndex: Int

  /// Returns if we are currently running on the executor.
  internal var onExecutor: Bool {
    return self.thread?.isCurrent ?? false
  }

  /// Creates a new platform-native task executor.
  ///
  /// This method creates a task executor backed by a dedicated pthread and ensures proper
  /// thread lifecycle management. The executor's thread will be automatically stopped and
  /// joined when the body closure completes, ensuring no thread leaks.
  ///
  /// - Parameters:
  ///   - name: The name assigned to the executor's background thread.
  ///   - stackSize: The stack size in bytes of the executor's background thread, or `nil` to use the
  ///     platform's default thread stack size. Must be greater than 0. The value is rounded up to a multiple
  ///     of the page size and to at least 128 KiB, or the platform's minimum thread stack size if larger.
  ///   - body: A closure that gets access to the task executor for the duration of execution.
  /// - Returns: The value returned by the body closure.
  package nonisolated(nonsending) static func withExecutor<Return, Failure: Error>(
    name: String,
    stackSize: Int? = nil,
    body: (PThreadExecutor) async throws(Failure) -> Return
  ) async throws(Failure) -> Return {
    do {
      return try await self._withExecutor(
        name: name,
        stackSize: stackSize,
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
    stackSize: Int? = nil,
    taskExecutor: UnownedTaskExecutor?,
    serialExecutor: UnownedSerialExecutor?,
    body: (PThreadExecutor) async throws -> Return
  ) async rethrows -> Return {
    let executor = PThreadExecutor(
      name: name,
      stackSize: stackSize,
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
    stackSize: Int? = nil,
    poolIndex: Int = 0,
    serialExecutor: UnownedSerialExecutor?,
    taskExecutor: UnownedTaskExecutor?
  ) {
    self.init(poolIndex: poolIndex)

    let conditionVariable = ConditionVariable(true)
    let thread = Thread.spawnAndRun(name: name, stackSize: stackSize) {
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

    self.thread = .some(consume thread)

    // Signal that we've set the thread in the thread bound state
    conditionVariable.signal { $0.toggle() }

    // Block until we've started running
    conditionVariable.wait {
      $0
    } block: { _ in
    }
  }

  internal init(poolIndex: Int = 0) {
    self.poolIndex = poolIndex
    self._threadBoundState = .init(
      _nextExecutedJobs: ContiguousArray()
    )
    self.wakeupHandle = self._threadBoundState._backend.wakeupHandle
  }

  deinit {
    precondition(
      self._multiThreadedState.withLock { $0.jobs.queue.isEmpty },
      "PThreadExecutor had left over jobs when deiniting."
    )
    #if ExperimentalIO && !os(WASI)
    precondition(
      self._multiThreadedState.withLock { $0.submittedIOCommands.isEmpty },
      "PThreadExecutor had left over submitted I/O commands when deiniting."
    )
    #endif
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
    var thread: Thread? = nil
    swap(&self.thread, &thread)
    guard let thread else {
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
      let shouldWakeBackend = self._multiThreadedState.withLock { state in
        body(&state)
        guard state.pendingJobPop else {
          // We have to wake the backend and we are going to store that we are about to do that.
          state.pendingJobPop = true
          return true
        }
        // There is already a next tick scheduled so we don't have to wake the selector.
        return false
      }

      // We only need to wake up the backend if we're not in the executor. If we're in the executor already,
      // we're running a job already which means that we'll check at least once more if there are other jobs to run.
      // While we had the lock we also checked whether the executor was _already_ going to be woken.
      // This saves us a syscall on hot loops.
      //
      // In the future we'll use an MPSC queue here and that will complicate things, so we may get some spurious wakeups,
      // but as long as we're using the big dumb lock we can make this optimization safely.
      if shouldWakeBackend {
        // Nothing we can do really if we fail to wake the backend
        try? Backend.wakeup(self.wakeupHandle)
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

  /// Wakes the backend up, which means a call to `wait` unblocks.
  ///
  /// - Note: This can be called from any thread.
  internal func _wakeupBackend() throws {
    try Backend.wakeup(self.wakeupHandle)
  }

  /// Start processing the jobs and handle any I/O.
  ///
  /// This method will continue running and blocking if needed.
  internal func run(runJobSynchronously: (UnownedJob) -> Void) throws {
    if self.thread == nil {
      // The executor took over the calling thread, which does not have to be joined.
      self.thread = .some(Thread.current)
    }
    self.assertOnExecutor()

    // This is the outer loop that we use to block on our selector
    // and check if we should stop
    var stopConditionVariable: ConditionVariable<Bool>? = nil
    defer {
      stopConditionVariable?.signal { $0.toggle() }
    }

    // The I/O of a tick comes before its jobs, so the first tick waits with
    // `.now`. This executor is reachable for enqueues before its thread gets
    // here, so a job can already be queued, and a first tick that blocked would
    // relies on the wakeup that enqueuing it sent.
    var strategy = IOWaitStrategy.now

    while true {
      // Let's wait on the backend until an operation completes, a timer fires
      // or there is other work to do.
      #if ExperimentalIO
      try self._backend.wait(strategy: strategy, completions: &self._completions)
      #else
      try self._backend.wait(strategy: strategy)
      #endif

      // Our backend unblocked and we are going to pop some jobs.
      // From here until the queue runs empty another thread that enqueues
      // one does not have to wake the backend.
      self._multiThreadedState.withLock {
        $0.pendingJobPop = true
      }

      #if ExperimentalIO
      // Resuming a submitter runs its continuation which can lead to another
      // enqueue. In the future, we might even run the continuations inline by
      // donating our thread.
      #if !os(WASI)
      for (id, result) in self._completions {
        guard let resumption = self.inFlightIOOperations.removeValue(forKey: id) else {
          fatalError("The I/O backend reported a result for an operation that is not in flight")
        }
        resumption.resume(with: result)
      }
      #endif
      self._completions.removeAll(keepingCapacity: true)
      #endif

      var moreJobsQueued = false
      var nextContinuousClockDeadline: ContinuousClock.Instant?
      var nextSuspendingClockDeadline: SuspendingClock.Instant?

      // This is the inner loop that processes one tick at a time. It can run
      // multiple times without blocking on the selector if there are many jobs
      // to processes or jobs are enqueued during a tick.
      while true {
        (stopConditionVariable, moreJobsQueued, nextContinuousClockDeadline, nextSuspendingClockDeadline) = self
          ._multiThreadedState.withLock { state in
            #if ExperimentalIO && !os(WASI)
            // We got some I/O commands that we should apply.
            swap(&state.submittedIOCommands, &self.nextSubmittedIOCommands)
            #endif

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
              jobsCopy: &self.nextExecutedJobs,
              batchSize: Self.jobsBatchSize
            )

            if self.nextExecutedJobs.isEmpty {
              // We got no jobs to execute so we will block and need to be woken up.
              assert(moreJobsQueued == false)
              state.pendingJobPop = false
            }
            return (nil, moreJobsQueued, nextContinuousClockDeadline, nextSuspendingClockDeadline)
          }

        #if ExperimentalIO && !os(WASI)
        // Submit the commands talks to the backend.
        self.submitIOCommands()
        #endif

        if stopConditionVariable != nil {
          // We need to stop now and break out of the inner loop
          break
        }

        if self.nextExecutedJobs.isEmpty {
          // There are no more jobs to execute so we have to block now
          break
        }

        for job in self.nextExecutedJobs {
          runJobSynchronously(job)
        }

        // Remove all the just executed jobs but keep the capacity.
        self.nextExecutedJobs.removeAll(keepingCapacity: true)
      }

      if stopConditionVariable != nil {
        // We need to stop now and need to break out of the outer loop
        break
      }

      // How long the next tick waits follows from the jobs this one just ran.
      strategy = self.currentIOWaitStrategy(
        moreJobsQueued: moreJobsQueued,
        nextContinuousClockDeadline: nextContinuousClockDeadline,
        nextSuspendingClockDeadline: nextSuspendingClockDeadline
      )
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

  private func currentIOWaitStrategy(
    moreJobsQueued: Bool,
    nextContinuousClockDeadline: ContinuousClock.Instant?,
    nextSuspendingClockDeadline: SuspendingClock.Instant?,
  ) -> IOWaitStrategy {
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
      fatalError("Unsupported clock")
    //      clock.enqueue(
    //        job,
    //        on: self,
    //        at: instant,
    //        tolerance: tolerance
    //      )
    }
  }
}
#endif

#if ExperimentalIO
@available(anyAppleOS 27.0, *)
#else
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
#endif
extension PThreadExecutor: CustomStringConvertible {
  package var description: String {
    "PThreadExecutor(\(self.threadDescription))"
  }
}

#if ExperimentalIO && !os(WASI)

/// I/O work that another thread submitted to the executor's thread.
@available(anyAppleOS 27.0, *)
internal enum SubmittedIOCommand: ~Copyable, Sendable {
  /// Submit the operation to the backend, resuming the given resumption once it completes.
  case submit(IOOperation, IOOperationID, PThreadExecutor.Resumption)

  /// Cancel the operation with the given identity.
  case cancel(IOOperationID)
}

// MARK: - Per-operation state

@available(anyAppleOS 27.0, *)
extension PThreadExecutor {
  /// The state that a ``PThreadExecutor`` needs per in-flight operation.
  package typealias OperationState = PThreadOperationState
}

@available(anyAppleOS 27.0, *)
extension PThreadExecutor {
  /// What an in-flight operation resumes when its result arrives.
  internal enum Resumption: ~Copyable {
    /// Resumes with a connected socket.
    case connection(Continuation<TCPConnection, IOError>, socket: CInt, executorIndex: Int)

    /// Resumes with the connection that an accept produced.
    case acceptedConnection(Continuation<TCPConnection, IOError>, executorIndex: Int)

    /// Resumes with the number of bytes that a read or a write transferred.
    case byteCount(Continuation<Int, IOError>)

    /// Resumes with void, so the result only reports whether the operation succeeded.
    case void(Continuation<Void, IOError>)

    /// Resumes the continuation with the result that the backend reported.
    internal consuming func resume(with result: Result<Int, IOError>) {
      switch consume self {
      case .connection(let continuation, let socket, let executorIndex):
        switch result {
        case .success:
          continuation.resume(returning: TCPConnection(fileDescriptor: socket, executorIndex: executorIndex))
        case .failure(let error):
          // We created the socket so we have to close it
          // TODO: In the future with io_uring we need to go through the backend
          // since io_uring should create the socket with `IORING_OP_SOCKET`.
          try? StreamSocketSyscall.close(socket)
          continuation.resume(throwing: error)
        }

      case .acceptedConnection(let continuation, let executorIndex):
        switch result {
        case .success(let fileDescriptor):
          continuation.resume(
            returning: TCPConnection(fileDescriptor: CInt(fileDescriptor), executorIndex: executorIndex)
          )
        case .failure(let error):
          continuation.resume(throwing: error)
        }

      case .byteCount(let continuation):
        continuation.resume(with: result)

      case .void(let continuation):
        switch result {
        case .success:
          continuation.resume()
        case .failure(let error):
          continuation.resume(throwing: error)
        }
      }
    }
  }

  /// The registration of an operation that completed synchronously.
  internal static var completedRegistration: OperationRegistration {
    OperationRegistration(id: 0)
  }
}

// MARK: - Submitting

@available(anyAppleOS 27.0, *)
extension PThreadExecutor {
  /// Submits the operation and holds on to what to resume once it completes.
  ///
  /// - Parameters:
  ///   - resumption: What to resume once the operation completes.
  ///   - request: The operation to perform.
  ///   - state: The state that the submitter allocated.
  /// - Returns: The registration of the operation.
  internal func submit(
    _ resumption: consuming Resumption,
    request: IORequest,
    state: inout OutputSpan<OperationState>
  ) -> OperationRegistration {
    precondition(
      !state.isFull,
      "The operation state of a PThreadExecutor needs capacity for one element"
    )
    // Everything the kernel reads is copied into the state to guarntee stable addresses.
    state.append(OperationState(address: request.address))

    let operation = Self.pin(request, in: &state)

    // We first try to attempt the operation if it can be done synchronously.
    if let result = Backend.attempt(operation) {
      resumption.resume(with: result)
      return Self.completedRegistration
    }

    let id = IOOperationID(
      rawValue: self._nextOperationID.wrappingAdd(1, ordering: .relaxed).oldValue
    )

    // If we are on the executor we can submit right away otherwise
    // we have to enqueue it and let the next tick pick it up.
    if self.onExecutor {
      let rejected = self.inFlightIOOperations.insertValue(
        resumption,
        forKey: id
      )
      guard case .none = consume rejected else {
        fatalError("An operation was submitted with the identity of one that is still in flight")
      }
      self._backend.submit(operation, id: id)
    } else {
      self.enqueue(.submit(operation, id, resumption))
    }

    return OperationRegistration(id: id.rawValue)
  }

  /// Pins everything that is needed in the request to the state to ensure we have a stable address.
  ///
  /// - Important: This has to pin every pointer that is passed to the kernel so it stays stable for
  /// the entire duration of the operation.
  ///
  /// - Parameters:
  ///   - request: The request to lower.
  ///   - state: The state that the submitter allocated.
  /// - Returns: The operation to submit.
  private static func pin(
    _ request: IORequest,
    in state: inout OutputSpan<OperationState>
  ) -> IOOperation {
    var states = state.mutableSpan
    return states.withUnsafeMutableBufferPointer { buffer in
      let statePointer = buffer.baseAddress! + (buffer.count - 1)
      switch request {
      case .connect(let socket, _):
        return .connect(
          socket: socket,
          address: UnsafePointer(statePointer.pointee.addressPointer),
          addressLength: statePointer.pointee.addressLength
        )
      case .accept(let socket):
        return .accept(socket: socket)
      case .read(let socket, let buffer):
        return .read(socket: socket, buffer: buffer)
      case .write(let socket, let buffer):
        return .write(socket: socket, buffer: buffer)
      case .shutdown(let socket, let direction):
        return .shutdown(socket: socket, direction: direction)
      case .close(let socket):
        return .close(socket: socket)
      }
    }
  }

  /// Hands the work to the executor's thread.
  private func enqueue(_ submitted: consuming SubmittedIOCommand) {
    var submitted = Optional(consume submitted)
    self.modifyMultiThreadedStateAndWakeUpIfNeeded { state in
      state.submittedIOCommands.append(submitted.take()!)
    }
  }

  package func cancel(_ registration: OperationRegistration) {
    guard registration.id != 0 else {
      // The operation completed before it was submitted
      // so there is nothing to cancel.
      return
    }

    let id = IOOperationID(rawValue: registration.id)

    // If we are on the executor and the operation reached the backend we can
    // cancel right away. Otherwise we have to enqueue it and let the next tick pick it up.
    if self.onExecutor && self.inFlightIOOperations.containsKey(id) {
      self._backend.cancel(id)
    } else {
      self.enqueue(.cancel(id))
    }
  }

  package func escalatePriority(
    of registration: OperationRegistration,
    to newPriority: TaskPriority
  ) {
    // Neither a readiness based nor a completion based mechanism
    // can re-prioritize an operation that is already submitted,
    // so there is nothing to do here.
  }
}

// MARK: - Running on the executor's thread

@available(anyAppleOS 27.0, *)
extension PThreadExecutor {
  /// Submits the I/O commands that other threads enqueued over to this thread.
  private func submitIOCommands() {
    // The commands are applied in the order they were enqueued.
    while let submitted = self.nextSubmittedIOCommands.popFirst() {
      switch consume submitted {
      case .submit(let operation, let id, let resumption):
        let rejected = self.inFlightIOOperations.insertValue(
          resumption,
          forKey: id
        )
        guard case .none = consume rejected else {
          fatalError("An operation was submitted with the identity of one that is still in flight")
        }
        self._backend.submit(operation, id: id)
      case .cancel(let id):
        // A cancellation can arrive after its operation completed
        // so we filter out anything that is no longer in-flight.
        if self.inFlightIOOperations.containsKey(id) {
          self._backend.cancel(id)
        }
      }
    }
  }
}

// MARK: - Addresses in the operation state

@available(anyAppleOS 27.0, *)
extension PThreadExecutor.OperationState {
  /// A pointer to the address storage of this state.
  ///
  /// - Important: This is only safe if the memory address is actually pinned.
  fileprivate var addressPointer: UnsafeMutablePointer<sockaddr> {
    mutating get {
      withUnsafeMutablePointer(to: &self.address) {
        UnsafeMutableRawPointer($0).assumingMemoryBound(to: sockaddr.self)
      }
    }
  }
}
#endif

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
