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
    /// Indicates if the executor should stop.
    var shouldStop = false
    /// This is the queue of enqueued jobs that we have to execute in the order they got enqueued.
    var jobs = NonCopyablePriorityQueue()
  }

  /// This is the state that is bound to this thread.
  struct ThreadBoundState: ~Copyable {
    /// The executor's thread.
    fileprivate var thread: Thread?
    /// Indicates if the executor took over the calling thread
    fileprivate var tookOverThread: Bool = false

    func isOnThread() -> Bool {
      return self.thread?.isCurrentFunc() ?? false
    }

    /// The executor's selector.
    var selector: Selector {
      _read {
        assert(self.isOnThread())
        yield self._selector
      }
    }

    /// The jobs that are next in line to be executed.
    fileprivate var nextExecutedJobs: NonCopyablePriorityQueue {
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
    func wakeupSelector() throws {
      try self._selector.wakeup()
    }

    /// The backing storage for the selector.
    ///
    /// This is a force try since there really is no way to handle these errors and this should never fail.
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
          !$0
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
      _nextExecutedJobs: NonCopyablePriorityQueue()
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

  internal func stop() {
    self.modifyMultiThreadedStateAndWakeUpIfNeeded { state in
      state.shouldStop = true
    }
  }

  internal func shutdown() {
    self.stop()
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
  package var description: String {
    "PThreadExecutor(\(self._threadBoundState.thread?.description ?? "not running"))"
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
private struct NonCopyablePriorityQueue: ~Copyable {
  var queue: PriorityQueue<UnownedJob>

  init() {
    if #available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *) {
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
#endif
