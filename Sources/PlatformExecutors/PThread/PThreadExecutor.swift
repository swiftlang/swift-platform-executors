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
#if ExperimentalIO
@_spi(SplitContinuation) import _Concurrency
#endif
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
@safe
package final class PThreadExecutor: TaskExecutor, @unchecked Sendable {
  /// The mechanism that performs this executor's I/O.
  typealias Backend = PlatformIOBackend

  /// The executor context passed when running jobs or resuming continuations.
  // TODO: We should drop the TaskExecutor conformance of PThreadExecutor
  // in the future and also support passing both a serial and task executor
  // once the runtime fixes its execution context handling.
  @safe
  enum ExecutionContext {
    case thisExecutor
    case task(UnownedTaskExecutor)
    case serial(UnownedSerialExecutor)
  }

  /// This is the state that is accessed from multiple threads; hence, it must be protected via a lock.
  @safe private struct MultiThreadedState: ~Copyable {
    /// Indicates if we are running and about to pop more jobs. If this is true then we don't have to wake the selector.
    var pendingJobPop = false
    /// The condition variable that gets signalled once the thread is stopped.
    var stopConditionVariable: ConditionVariable<Bool>? = nil
    #if ExperimentalIO && !os(WASI)
    /// The I/O work that other threads handed to the executor's thread.
    var submittedIOCommands = unsafe UniqueDeque<SubmittedIOCommand>()
    #endif
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
  @safe struct ThreadBoundState: ~Copyable {
    /// The backing storage for the backend.
    var _backend: Backend

    /// The backing storage of the next executed jobs.
    fileprivate var _nextExecutedJobs: ContiguousArray<UnownedJob>

    /// The jobs that were drained from the inbox, in the order they have to be executed in.
    fileprivate var _jobs = JobQueue()

    #if ExperimentalIO && !os(WASI)
    /// The backing storage of the next submitted I/O commands.
    fileprivate var _nextSubmittedIOCommands = unsafe UniqueDeque<SubmittedIOCommand>()

    /// The backing storage of the in-flight I/O operations.
    ///
    /// This is a `RigidDictionary`, since a `UniqueDictionary` shrinks when operations complete and has to
    /// grow again when the next ones are submitted.
    fileprivate var _inFlightIOOperations = RigidDictionary<IOOperationID, Resumption>(
      capacity: IOOperation.reservedCapacity
    )
    #endif

    fileprivate init(_nextExecutedJobs: consuming ContiguousArray<UnownedJob>, ioBackend: PThreadIOBackend) {
      self._backend = Backend(ioBackend)
      self._nextExecutedJobs = _nextExecutedJobs
    }
  }

  /// This is the state that is accessed from multiple threads; hence, it is protected via a lock.
  ///
  /// - Note:In the future we could use an MPSC queue and atomics here.
  private let _multiThreadedState = Mutex(MultiThreadedState())

  /// This is the backing state that is accessed from the thread backing the executor.
  private var _threadBoundState: ThreadBoundState

  /// This is the state that is accessed from the thread backing the executor.
  private var threadBoundState: ThreadBoundState {
    _read {
      assert(self.onExecutor)
      yield self._threadBoundState
    }
    _modify {
      assert(self.onExecutor)
      yield &self._threadBoundState
    }
  }

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

  /// The jobs that were drained from the inbox and wait to be executed.
  private var jobs: JobQueue {
    _read {
      assert(self.onExecutor)
      yield self._threadBoundState._jobs
    }
    _modify {
      assert(self.onExecutor)
      yield &self._threadBoundState._jobs
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
      yield unsafe self._threadBoundState._nextSubmittedIOCommands
    }
    _modify {
      assert(self.onExecutor)
      yield unsafe &self._threadBoundState._nextSubmittedIOCommands
    }
  }

  /// The currently inflight I/O operations.
  private var inFlightIOOperations: RigidDictionary<IOOperationID, Resumption> {
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

  /// The inbox that other threads put jobs into without taking a lock.
  ///
  /// This is a stack of the jobs themselves, newest first, that the executor's thread takes in one go. A value of zero
  /// means that it is empty. ``inboxSleeping`` means that it is empty and that the executor's thread is about to
  /// wait, or is waiting, on its backend and must be woken up by whoever puts the next job into it.
  private let inbox = Atomic<UInt>(0)

  /// The marker in ``inbox`` for an executor that waits. No job can have this address.
  private static var inboxSleeping: UInt { 1 }

  /// The next sequence number of an enqueued jobs.
  private let sequenceNumber = Atomic<UInt64>(0)

  /// The thread that runs this executor.
  private var thread: Thread?

  /// The identity of the thread that runs this executor while it runs and zero otherwise.
  private let runningThreadIdentity = Atomic<UInt>(0)

  /// The handle that wakes the backend up from another thread.
  ///
  /// This is held separately so waking the executor up never touches its thread bound state.
  private let wakeupHandle: Backend.WakeupHandle

  #if ExperimentalIO && !os(WASI)
  /// The identity of the next submitted operation.
  private let _nextOperationID = Atomic<UInt>(1)
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

  /// The execution context used when running jobs or resuming continuations.
  ///
  /// - Note: This is set before the executor's thread starts and read once when it starts running.
  internal var executionContext = ExecutionContext.thisExecutor

  /// Returns if we are currently running on the executor.
  internal var onExecutor: Bool {
    return self.runningThreadIdentity.load(ordering: .relaxed) == PThread.currentThreadIdentity
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
  ///   - ioBackend: The mechanism that the executor's thread waits for events and performs its I/O with.
  ///   - body: A closure that gets access to the task executor for the duration of execution.
  /// - Returns: The value returned by the body closure.
  package nonisolated(nonsending) static func withExecutor<Return, Failure: Error>(
    name: String,
    stackSize: Int? = nil,
    ioBackend: PThreadIOBackend = .platformDefault,
    body: (PThreadExecutor) async throws(Failure) -> Return
  ) async throws(Failure) -> Return {
    do {
      return try await unsafe self._withExecutor(
        name: name,
        stackSize: stackSize,
        taskExecutor: nil,
        serialExecutor: nil,
        ioBackend: ioBackend,
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
    ioBackend: PThreadIOBackend = .platformDefault,
    body: (PThreadExecutor) async throws -> Return
  ) async rethrows -> Return {
    let executor = unsafe PThreadExecutor(
      name: name,
      stackSize: stackSize,
      serialExecutor: serialExecutor,
      taskExecutor: taskExecutor,
      ioBackend: ioBackend
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
    taskExecutor: UnownedTaskExecutor?,
    ioBackend: PThreadIOBackend = .platformDefault
  ) {
    self.init(poolIndex: poolIndex, ioBackend: ioBackend)

    // It is incredibly important that we pass the right task executor
    // to the run methods otherwise the Concurrency runtime will re-enqueue
    // the task over and over again. If this executor is part of a thread pool
    // then we must pass the pool as the executor.
    if unsafe taskExecutor != nil, unsafe serialExecutor != nil {
      // TODO: This is currently not supported because the runtime doesn't handle
      // it correctly.
      fatalError("Currently not supported to run as both serial and task executor")
    } else if let taskExecutor = unsafe taskExecutor {
      self.executionContext = unsafe .task(taskExecutor)
    } else if let serialExecutor = unsafe serialExecutor {
      self.executionContext = unsafe .serial(serialExecutor)
    }

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

        try self.run()
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

  internal init(poolIndex: Int = 0, ioBackend: PThreadIOBackend = .platformDefault) {
    self.poolIndex = poolIndex
    self._threadBoundState = .init(
      _nextExecutedJobs: ContiguousArray(),
      ioBackend: ioBackend
    )
    self.wakeupHandle = self._threadBoundState._backend.wakeupHandle
  }

  deinit {
    precondition(
      self.inbox.load(ordering: .relaxed) <= Self.inboxSleeping,
      "PThreadExecutor had left over jobs when deiniting."
    )
    #if ExperimentalIO && !os(WASI)
    precondition(
      self._multiThreadedState.withLock { unsafe $0.submittedIOCommands.isEmpty },
      "PThreadExecutor had left over submitted I/O commands when deiniting."
    )
    #endif
  }

  package func enqueue(_ job: consuming ExecutorJob) {
    // The job is its own node. The jobs of the inbox are ordered by when they were put into it, so they do not need a
    // sequence number.
    let unownedJob = UnownedJob(job)
    let address = unsafe unsafeBitCast(unownedJob, to: UInt.self)
    var head = self.inbox.load(ordering: .relaxed)
    while true {
      var node = ExecutorJob(unownedJob)
      node.inboxNext = head == Self.inboxSleeping ? 0 : head
      // The release publishes the job, including the link to the next one,
      // to the executor's thread, which acquires it when it drains the inbox.
      // The jobs of other producers that this one links to are published
      // by their own compare-exchanges.
      let (exchanged, original) = self.inbox.compareExchange(
        expected: head,
        desired: address,
        ordering: .acquiringAndReleasing
      )
      if exchanged {
        break
      }
      head = original
    }

    // Only the first job that arrives while the executor waits has to wake it.
    if head == Self.inboxSleeping {
      // Nothing we can do really if we fail to wake the backend
      try? Backend.wakeup(self.wakeupHandle)
    }
  }

  /// Moves the jobs that other threads put into the inbox over to the executor's queue of jobs.
  private func drainInbox() {
    // The acquire makes the jobs that the producers released visible.
    // There is nothing to publish to the producers, which only ever look at
    // the value of the inbox.
    var cursor = self.inbox.exchange(0, ordering: .acquiring)
    guard cursor > Self.inboxSleeping else {
      return
    }

    // The inbox is a stack, so the newest job comes first. Reverse the list in place to push the jobs in the order
    // they arrived in.
    var oldestFirst: UInt = 0
    while cursor != 0 {
      let job = unsafe unsafeBitCast(cursor, to: UnownedJob.self)
      let next = ExecutorJob(job).inboxNext
      var node = ExecutorJob(job)
      node.inboxNext = oldestFirst
      oldestFirst = cursor
      cursor = next
    }

    while oldestFirst != 0 {
      let job = unsafe unsafeBitCast(oldestFirst, to: UnownedJob.self)
      oldestFirst = ExecutorJob(job).inboxNext
      self.jobs.push(ExecutorJob(job))
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

  /// Returns a closure that runs a job on ``executionContext``.
  internal func makeJobRunner() -> (UnownedJob) -> Void {
    switch self.executionContext {
    case .thisExecutor:
      let taskExecutor = unsafe self.asUnownedTaskExecutor()
      return { job in unsafe job.runSynchronously(on: taskExecutor) }
    case .task(let taskExecutor):
      return { job in unsafe job.runSynchronously(on: taskExecutor) }
    case .serial(let serialExecutor):
      return { job in unsafe job.runSynchronously(on: serialExecutor) }
    }
  }

  /// Start processing the jobs and handle any I/O.
  ///
  /// This method will continue running and blocking if needed.
  internal func run() throws {
    if self.thread == nil {
      // The executor took over the calling thread, which does not have to be joined.
      self.thread = .some(Thread.current)
    }
    // This is cleared before the thread can end since a later thread can have the same identity.
    self.runningThreadIdentity.store(PThread.currentThreadIdentity, ordering: .relaxed)
    defer { self.runningThreadIdentity.store(0, ordering: .relaxed) }
    self.assertOnExecutor()

    // We are creating our job runner and continuation resumer once to avoid
    // any per-job/continuation overhead.
    let runJob = self.makeJobRunner()
    #if ExperimentalIO && !os(WASI)
    let continuationResumer = self.makeContinuationResumer()
    #endif

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

    #if ExperimentalIO
    // The results of the operations that the backend handed over in a tick.
    var completions = [(IOOperationID, Result<Int, IOError>)]()
    completions.reserveCapacity(IOOperation.reservedCapacity)
    #endif

    while true {
      // Let's wait on the backend until an operation completes, a timer fires
      // or there is other work to do.
      #if ExperimentalIO
      try self._backend.wait(strategy: strategy, completions: &completions)
      #else
      try self._backend.wait(strategy: strategy)
      #endif

      #if ExperimentalIO
      // Resuming a submitter runs its continuation which can lead to another
      // enqueue. In the future, we might even run the continuations inline by
      // donating our thread.
      #if !os(WASI)
      for (id, result) in completions {
        guard let resumption = self.inFlightIOOperations.removeValue(forKey: id) else {
          fatalError("The I/O backend reported a result for an operation that is not in flight")
        }
        resumption.resume(with: result, using: continuationResumer)
      }
      #endif
      completions.removeAll(keepingCapacity: true)
      #endif

      var moreJobsQueued = false
      var nextContinuousClockDeadline: ContinuousClock.Instant?
      var nextSuspendingClockDeadline: SuspendingClock.Instant?

      // This is the inner loop that processes one tick at a time. It can run
      // multiple times without blocking on the selector if there are many jobs
      // to processes or jobs are enqueued during a tick.
      while true {
        // Jobs that other threads enqueued without taking the lock.
        self.drainInbox()

        (stopConditionVariable, moreJobsQueued, nextContinuousClockDeadline, nextSuspendingClockDeadline) = self
          ._multiThreadedState.withLock { state in
            // From here until the queues run empty another thread that enqueues
            // a job with a deadline or an I/O command does not have to wake the backend.
            state.pendingJobPop = true

            #if ExperimentalIO && !os(WASI)
            // We got some I/O commands that we should apply.
            unsafe swap(&state.submittedIOCommands, &self.nextSubmittedIOCommands)
            #endif

            // We were flagged to stop so we need to exit this loop
            if let stopConditionVariable = state.stopConditionVariable.take() {
              return (stopConditionVariable, false, nil, nil)
            }
            // We got some jobs that we should execute. Let's copy them over so we can
            // give up the lock.
            let (moreJobsQueued, nextContinuousClockDeadline, nextSuspendingClockDeadline) = Self._popJobsLocked(
              threadBoundState: &self.threadBoundState,
              continuousClockJobs: &state.continuousClockJobs,
              suspendingClockJobs: &state.suspendingClockJobs,
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
          runJob(job)
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

      // Announce that we wait unless a job arrived in the meantime. A thread
      // that enqueues a job after this sees the marker and wakes us, and one
      // that did so before makes the exchange fail. The acquire keeps the wait
      // from starting before the announcement took effect.
      if case .now = strategy {
      } else if !self.inbox.compareExchange(
        expected: 0,
        desired: Self.inboxSleeping,
        ordering: .acquiringAndReleasing
      ).exchanged {
        strategy = .now
      }
    }
  }

  private static func _popJobsLocked(
    threadBoundState: inout ThreadBoundState,
    continuousClockJobs: inout NonCopyablePriorityQueue<(ContinuousClock.Instant, UnownedJob)>,
    suspendingClockJobs: inout NonCopyablePriorityQueue<(SuspendingClock.Instant, UnownedJob)>,
    batchSize: Int
  ) -> (Bool, ContinuousClock.Instant?, SuspendingClock.Instant?) {
    // We expect empty threadBoundState._nextExecutedJobs, to put a new batch of tasks into
    assert(threadBoundState._nextExecutedJobs.isEmpty)

    var moreJobsToConsider = !threadBoundState._jobs.isEmpty
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
      if moreJobsToConsider, threadBoundState._nextExecutedJobs.count < batchSize,
        let job = threadBoundState._jobs.pop()
      {
        threadBoundState._nextExecutedJobs.append(UnownedJob(job))
      } else {
        moreJobsToConsider = false
      }

      if moreContinuousClockJobsToConsider, threadBoundState._nextExecutedJobs.count < batchSize,
        let job = continuousClockJobs.peek()
      {
        if continuousClockNow.duration(to: job.0) <= .nanoseconds(0) {
          _ = continuousClockJobs.pop()
          threadBoundState._nextExecutedJobs.append(job.1)
        } else {
          nextContinuousClockDeadline = job.0
          moreContinuousClockJobsToConsider = false
        }
      } else {
        moreContinuousClockJobsToConsider = false
      }

      if moreSuspendingClockJobsToConsider, threadBoundState._nextExecutedJobs.count < batchSize,
        let job = suspendingClockJobs.peek()
      {
        if suspendingClockNow.duration(to: job.0) <= .nanoseconds(0) {
          _ = suspendingClockJobs.pop()
          threadBoundState._nextExecutedJobs.append(job.1)
        } else {
          nextSuspendingClockDeadline = job.0
          moreSuspendingClockJobsToConsider = false
        }
      } else {
        moreSuspendingClockJobsToConsider = false
      }
    }

    return (!threadBoundState._jobs.isEmpty, nextContinuousClockDeadline, nextSuspendingClockDeadline)
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
    guard nextContinuousClockDeadline != nil || nextSuspendingClockDeadline != nil else {
      // Nothing is scheduled so we block without reading the clocks.
      return .block
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
  package var asSchedulingExecutor: (any SchedulingExecutor)? {
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
@unsafe internal enum SubmittedIOCommand: ~Copyable, Sendable {
  /// Submit the operation to the backend, resuming the given resumption once it completes.
  case submit(IOOperation, IOOperationID, PThreadExecutor.Resumption)

  /// Cancel the operation with the given identity.
  case cancel(IOOperationID)
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

    /// Resumes the continuation with the result that the backend reported
    ///
    /// - Parameters:
    ///   - result: The result that the backend reported.
    ///   - resumer: The resumer that offers the current thread to the resumed task.
    internal consuming func resume(
      with result: Result<Int, IOError>,
      using resumer: ContinuationResumer
    ) {
      switch consume self {
      case .connection(let continuation, let socket, let executorIndex):
        switch result {
        case .success:
          resumer.resumeConnection(
            continuation,
            .success(TCPConnection(fileDescriptor: socket, executorIndex: executorIndex))
          )
        case .failure(let error):
          try? StreamSocketSyscall.close(socket)
          resumer.resumeConnection(continuation, .failure(error))
        }

      case .acceptedConnection(let continuation, let executorIndex):
        switch result {
        case .success(let fileDescriptor):
          resumer.resumeConnection(
            continuation,
            .success(TCPConnection(fileDescriptor: CInt(fileDescriptor), executorIndex: executorIndex))
          )
        case .failure(let error):
          resumer.resumeConnection(continuation, .failure(error))
        }

      case .byteCount(let continuation):
        resumer.resumeByteCount(continuation, result)

      case .void(let continuation):
        resumer.resumeVoid(continuation, result.map { _ in () })
      }
    }

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
}

@available(anyAppleOS 27.0, *)
extension PThreadExecutor {
  /// Resumes continuations, offering the current thread to the resumed tasks.
  internal struct ContinuationResumer {
    /// Resumes a continuation that produces a connection.
    let resumeConnection: (consuming Continuation<TCPConnection, IOError>, Result<TCPConnection, IOError>) -> Void

    /// Resumes a continuation that produces a number of bytes.
    let resumeByteCount: (consuming Continuation<Int, IOError>, Result<Int, IOError>) -> Void

    /// Resumes a continuation that only reports whether its operation succeeded.
    let resumeVoid: (consuming Continuation<Void, IOError>, Result<Void, IOError>) -> Void

    /// Creates a resumer whose resumed tasks run inline if they run on the given task executor.
    init(taskExecutor: UnownedTaskExecutor) {
      self.resumeConnection = { continuation, result in
        unsafe continuation.resume(with: result, on: taskExecutor)
      }
      self.resumeByteCount = { continuation, result in
        unsafe continuation.resume(with: result, on: taskExecutor)
      }
      self.resumeVoid = { continuation, result in
        unsafe continuation.resume(with: result, on: taskExecutor)
      }
    }

    /// Creates a resumer whose resumed tasks run inline if they are isolated to the given serial executor.
    init(serialExecutor: UnownedSerialExecutor) {
      self.resumeConnection = { continuation, result in
        unsafe continuation.resume(with: result, isolatedTo: serialExecutor)
      }
      self.resumeByteCount = { continuation, result in
        unsafe continuation.resume(with: result, isolatedTo: serialExecutor)
      }
      self.resumeVoid = { continuation, result in
        unsafe continuation.resume(with: result, isolatedTo: serialExecutor)
      }
    }
  }

  /// Returns a resumer that offers the current thread to resumed tasks that run on ``executionContext``.
  internal func makeContinuationResumer() -> ContinuationResumer {
    switch self.executionContext {
    case .thisExecutor:
      return unsafe ContinuationResumer(taskExecutor: self.asUnownedTaskExecutor())
    case .task(let taskExecutor):
      return unsafe ContinuationResumer(taskExecutor: taskExecutor)
    case .serial(let serialExecutor):
      return unsafe ContinuationResumer(serialExecutor: serialExecutor)
    }
  }
}

// MARK: - Submitting

@available(anyAppleOS 27.0, *)
extension PThreadExecutor {
  /// Performs the operation and awaits its result.
  ///
  /// - Important: Every pointer in the operation has to stay valid until this method returns.
  ///
  /// - Parameters:
  ///   - operation: The operation to perform.
  ///   - resumption: Returns what to resume with the given continuation once the operation completes.
  /// - Returns: The result of the operation.
  internal nonisolated(nonsending) func perform<Success: ~Copyable>(
    _ operation: IOOperation,
    resumption: (consuming Continuation<Success, IOError>) -> Resumption
  ) async throws(IOError) -> Success {
    try await withContinuation(
      of: Success.self,
      throwing: IOError.self
    ) { (continuation, awaiter) async throws(IOError) -> Success in
      guard let id = unsafe self.submit(operation, resuming: resumption(continuation)) else {
        // The operation completed synchronously, so there is nothing
        // to cancel and no reason to install the handlers.
        return try await awaiter.wait()
      }
      return try await awaiter.wait(
        onCancel: { self.cancel(id) },
        onEscalate: { newPriority in self.escalatePriority(of: id, to: newPriority) }
      )
    }
  }

  /// Submits the operation and holds on to what to resume once it completes.
  ///
  /// - Parameters:
  ///   - operation: The operation to perform.
  ///   - resumption: What to resume once the operation completes.
  /// - Returns: The identity of the operation, or `nil` if it completed synchronously.
  internal func submit(
    _ operation: IOOperation,
    resuming resumption: consuming Resumption
  ) -> IOOperationID? {
    // We first try to attempt the operation if it can be done synchronously.
    if let result = unsafe Backend.attempt(operation, handle: self.wakeupHandle) {
      resumption.resume(with: result)
      return nil
    }

    let id = IOOperationID(
      rawValue: self._nextOperationID.wrappingAdd(1, ordering: .relaxed).oldValue
    )

    // If we are on the executor we can submit right away otherwise
    // we have to enqueue it and let the next tick pick it up.
    if self.onExecutor {
      unsafe self.threadBoundState.submit(operation, id: id, resuming: resumption)
    } else {
      unsafe self.enqueue(.submit(operation, id, resumption))
    }

    return id
  }

  /// Hands the work to the executor's thread.
  private func enqueue(_ submitted: consuming SubmittedIOCommand) {
    var submitted = unsafe Optional(consume submitted)
    self.modifyMultiThreadedStateAndWakeUpIfNeeded { state in
      unsafe state.submittedIOCommands.append(submitted.take()!)
    }
  }

  /// Cancels the operation with the given identity.
  ///
  /// - Parameter id: The identity of the operation.
  internal func cancel(_ id: IOOperationID) {
    // If we are on the executor and the operation reached the backend we can
    // cancel right away. Otherwise we have to enqueue it and let the next tick pick it up.
    if self.onExecutor && self.threadBoundState.cancelIfInFlight(id) {
      return
    }
    unsafe self.enqueue(.cancel(id))
  }

  /// Escalates the priority of the operation with the given identity.
  ///
  /// - Parameters:
  ///   - id: The identity of the operation.
  ///   - newPriority: The new priority to set.
  internal func escalatePriority(
    of id: IOOperationID,
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
    self.threadBoundState.applySubmittedIOCommands()
  }
}

@available(anyAppleOS 27.0, *)
extension PThreadExecutor.ThreadBoundState {
  /// Submits the operation to the backend and holds on to what to resume once it completes.
  ///
  /// - Parameters:
  ///   - operation: The operation to perform.
  ///   - id: The identity of the operation.
  ///   - resumption: What to resume once the operation completes.
  fileprivate mutating func submit(
    _ operation: IOOperation,
    id: IOOperationID,
    resuming resumption: consuming PThreadExecutor.Resumption
  ) {
    // There is no more room in the dictionary so we have to grow it.
    if self._inFlightIOOperations.isFull {
      self._inFlightIOOperations.reserveCapacity(2 * self._inFlightIOOperations.capacity)
    }
    let rejected = self._inFlightIOOperations.insertValue(resumption, forKey: id)
    guard case .none = consume rejected else {
      fatalError("An operation was submitted with the identity of one that is still in flight")
    }
    unsafe self._backend.submit(operation, id: id)
  }

  /// Cancels the operation with the given identity if it reached the backend and has not completed.
  ///
  /// - Parameter id: The identity of the operation.
  /// - Returns: Whether the operation was in flight.
  fileprivate mutating func cancelIfInFlight(_ id: IOOperationID) -> Bool {
    guard self._inFlightIOOperations.containsKey(id) else {
      return false
    }
    self._backend.cancel(id)
    return true
  }

  /// Applies the I/O commands that other threads enqueued, in the order they were enqueued.
  fileprivate mutating func applySubmittedIOCommands() {
    while let submitted = unsafe self._nextSubmittedIOCommands.popFirst() {
      switch unsafe consume submitted {
      case .submit(let operation, let id, let resumption):
        unsafe self.submit(operation, id: id, resuming: resumption)
      case .cancel(let id):
        // A cancellation can arrive after its operation completed
        // so we filter out anything that is no longer in-flight.
        _ = self.cancelIfInFlight(id)
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
