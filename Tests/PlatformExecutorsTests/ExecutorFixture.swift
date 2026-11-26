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

@_spi(ExperimentalScheduling) @_spi(ConcurrencyExecutors) @_spi(ExperimentalCustomExecutors) import _Concurrency
@_spi(ExperimentalScheduling) @_spi(ConcurrencyExecutors) @_spi(ExperimentalCustomExecutors) import PlatformExecutors
import Synchronization

// When testing waiting for a delay D, the tests will tolerate a delay
// up to 25% longer, i.e.
//
//   Dmax = D + D/4
//
// However, for smaller delays this may still not be sufficient,
// particularly in CI where we need to tolerate noisy neighbours.
//
// We therefore apply a floor to the 25% extra that we tolerate,
// making
//
//   Dmax = D + max(D/4, maxDelayTolerance)
//
private let maxDelayTolerance = 250  // ms

// For the Thread Pool executor, we can return slightly early
private let minDelayTolerance = 2  // ms

// The order checks let a job run before another job whose deadline came at most
// this much earlier. The nominal deadlines are at least 15 ms apart, so this only
// matters when a pause in the enqueuing loop pushed two deadlines together, and
// timer jitter between the threads of a pool can then swap them.
private let orderingSlack = 10  // ms

@available(macOS 9999, *)
func createJob(
  priority: TaskPriority,
  _ body: @escaping () -> Void
) -> ExecutorJob {
  // We use this undocumented function to allow for direct testing of executors
  return _swift_createJobForTestingOnly(priority: priority, body)
}

@available(macOS 9999, *)
struct ExecutorFixture {
  static func test(executor: some Executor) async -> Bool {
    var result = true
    print("Testing \(executor)")
    if let runLoopExecutor = executor as? any RunLoopExecutor {
      result = await test(runLoopExecutor: runLoopExecutor) && result
    }
    if let serialExecutor = executor as? any SerialExecutor {
      result = await test(serialExecutor: serialExecutor) && result
    }
    if let schedulingExecutor = executor as? any SchedulingExecutor {
      result = await test(schedulingExecutor: schedulingExecutor) && result
    }
    if let taskExecutor = executor as? any TaskExecutor {
      result = await test(taskExecutor: taskExecutor) && result
    }
    if result {
      print("** ALL TESTS PASSED")
    } else {
      print("** TESTS FAILED")
    }
    return result
  }

  static func test(runLoopExecutor: some RunLoopExecutor) async -> Bool {
    print("\no RunLoopExecutor")

    // Do this twice, to make sure we can start after stopping
    for _ in 0..<2 {
      let stopJob = createJob(priority: .medium) {
        print("  - stopping")
        runLoopExecutor.stop()
      }

      runLoopExecutor.enqueue(stopJob)

      print("  - running")
      try! runLoopExecutor.run()

      print("  - stopped")
    }

    return true
  }

  static func test(serialExecutor: some SerialExecutor) async -> Bool {
    print("\no SerialExecutor")

    let order = Mutex<[Int]>([])

    await withCheckedContinuation { continuation in
      let runLoopExecutor = serialExecutor as? (any RunLoopExecutor)

      // Enqueue the jobs from an enqueued job; this means that if the
      // executor does _not_ implement RunLoopExecutor, we can't be caught
      // out and end up running htem in the wrong order.
      //
      // (Otherwise, the executor might be running already, and could start
      // running mediumJob immediately before it has even seen highJob.)
      let enqueueJob = createJob(priority: .medium) {
        print("  - Enqueuing jobs")

        let highJob = createJob(priority: .high) {
          print("  - High priority job")
          order.withLock {
            $0.append(1)
          }
        }
        let highJob2 = createJob(priority: .high) {
          print("  - High priority job 2")
          order.withLock {
            $0.append(2)
          }
        }
        let mediumJob = createJob(priority: .medium) {
          print("  - Medium priority job")
          order.withLock {
            $0.append(3)
          }
        }
        let mediumJob2 = createJob(priority: .medium) {
          print("  - Medium priority job 2")
          order.withLock {
            $0.append(4)
          }
        }
        let lowJob = createJob(priority: .low) {
          print("  - Low priority job")
          order.withLock {
            $0.append(5)
          }
        }
        let lowJob2 = createJob(priority: .low) {
          print("  - Low priority job 2")
          order.withLock {
            $0.append(6)
          }
        }
        let stopJob = createJob(priority: .low) {
          print("  - Stopping (low priority job 3)")
          // If this executor implements RunLoopExecutor, stop it
          if let runLoopExecutor {
            print("  - Telling RunLoopExecutor to stop")
            runLoopExecutor.stop()
          }
          order.withLock {
            $0.append(7)
          }
          continuation.resume()
        }

        serialExecutor.enqueue(mediumJob)  // 3
        serialExecutor.enqueue(lowJob)  // 5
        serialExecutor.enqueue(highJob)  // 1
        serialExecutor.enqueue(lowJob2)  // 6
        serialExecutor.enqueue(mediumJob2)  // 4
        serialExecutor.enqueue(highJob2)  // 2
        serialExecutor.enqueue(stopJob)  // 7
      }
      serialExecutor.enqueue(enqueueJob)

      // If this executor implements RunLoopExecutor, run it
      if let runLoopExecutor {
        print("  - Telling RunLoopExecutor to run")
        try! runLoopExecutor.run()
      }
    }

    return order.withLock {
      if $0 != [1, 2, 3, 4, 5, 6, 7] {
        print("  * FAILED (\($0))")
        return false
      }
      print("  * OK")
      return true
    }
  }

  /// A scheduled job that ran, as the scheduling tests' order checks see it.
  private struct ScheduledRun<Instant: InstantProtocol> {
    /// The job's nominal delay in milliseconds, which names it in messages.
    var delay: Int
    /// The deadline the executor orders the job by lies between these two
    /// instants. It's fixed during the `enqueue` call, and a job enqueued after
    /// its target may be ordered by its target or as due once the executor has it.
    var earliestDeadline: Instant
    var latestDeadline: Instant
    /// When the `enqueue` call returned. The executor may have had the job earlier.
    var enqueueReturned: Instant
    var ran: Instant
  }

  /// Describes the first pair of jobs that ran out of order, or returns `nil`.
  ///
  /// A job must not run while a job with an earlier deadline is waiting. A pause
  /// in the enqueuing loop (a preempted thread, or a sanitizer printing a report,
  /// possibly inside `enqueue`) delays the later enqueues, and whether the jobs
  /// that come due during the pause run on time or only after the loop depends on
  /// whether the loop runs on the executor's own thread. So the check doesn't
  /// predict one order. It only rejects orders a correct executor can't produce:
  /// the other job's deadline came first by more than `slack`, and its `enqueue`
  /// call had returned more than `slack` before the first job ran.
  ///
  /// - Parameter runs: The jobs in the order they ran.
  private static func orderViolation<Instant: InstantProtocol>(
    _ runs: [ScheduledRun<Instant>],
    slack: Instant.Duration
  ) -> String? {
    for (index, first) in runs.enumerated() {
      for second in runs[(index + 1)...] {
        let secondWasDueFirst = second.latestDeadline.advanced(by: slack) < first.earliestDeadline
        let secondWasWaiting = second.enqueueReturned.advanced(by: slack) < first.ran
        if secondWasDueFirst && secondWasWaiting {
          return "the \(second.delay) ms job (due by \(second.latestDeadline)) ran at \(second.ran), "
            + "after the \(first.delay) ms job (due no earlier than \(first.earliestDeadline)) ran at \(first.ran)"
        }
      }
    }
    return nil
  }

  /// Describes the first `enqueue` call that blocked its caller for longer than
  /// `limit`, or returns `nil`.
  ///
  /// The order and lateness checks allow for a pause inside `enqueue`, so without
  /// this bound an executor whose `enqueue` sleeps until the deadline would pass.
  private static func slowEnqueue<Instant: InstantProtocol>(
    _ calls: [(delay: Int, start: Instant, returned: Instant)],
    limit: Instant.Duration
  ) -> String? {
    for call in calls where call.start.advanced(by: limit) < call.returned {
      return "enqueueing the \(call.delay) ms job took \(call.start.duration(to: call.returned))"
    }
    return nil
  }

  static func test<C: Clock, E: SchedulingExecutor>(
    schedulingExecutor: E,
    clock: C
  ) async -> Bool {
    print("\no SchedulingExecutor (\(clock))")
    let slack = Duration.milliseconds(orderingSlack) as! C.Duration
    let enqueueLimit = Duration.milliseconds(maxDelayTolerance) as! C.Duration

    print("  - Delays")
    let delays = [15, 30, 100, 250, 500, 1000]
    // The jobs in the order they ran, and when each ran.
    let delayedRuns = Mutex<[(delay: Int, ran: C.Instant)]>([])
    // `enqueue(_:after:)` counts each delay from the moment that job is enqueued,
    // so each job's deadline and delay are measured from its own `enqueue` call.
    let delayEnqueueStarts = Mutex<[Int: C.Instant]>([:])
    let delayEnqueueReturns = Mutex<[Int: C.Instant]>([:])

    await withCheckedContinuation { continuation in
      let runLoopExecutor = schedulingExecutor as? (any RunLoopExecutor)

      for delay in delays.reversed() {
        let job = createJob(priority: .medium) {
          let ran = clock.now
          let actualDelay = delayEnqueueStarts.withLock { $0[delay]! }.duration(to: ran)
          print("    + Delayed job (\(delay) ms, actual \(actualDelay))")
          delayedRuns.withLock {
            $0.append((delay, ran))
          }
        }
        let theDelay = Duration.milliseconds(delay) as! C.Duration
        // Taken before `enqueue`, so the job can't run before it's recorded, and
        // the measured delay can only come out slightly long, never short.
        delayEnqueueStarts.withLock {
          $0[delay] = clock.now
        }
        schedulingExecutor.enqueue(
          job,
          after: theDelay,
          clock: clock
        )
        delayEnqueueReturns.withLock {
          $0[delay] = clock.now
        }
      }
      let stopJob = createJob(priority: .low) {
        print("    + Stopping")
        if let runLoopExecutor {
          print("    + Telling RunLoopExecutor to stop")
          runLoopExecutor.stop()
        }
        continuation.resume()
      }
      let stopDelay = Duration.milliseconds(1100) as! C.Duration
      schedulingExecutor.enqueue(
        stopJob,
        after: stopDelay,
        clock: clock
      )
      if let runLoopExecutor {
        print("    + Telling RunLoopExecutor to run")
        try! runLoopExecutor.run()
      }
    }

    let result = delayedRuns.withLock { ranInOrder in
      let order = ranInOrder.map(\.delay)
      if order.sorted() != delays {
        let missing = Set(delays).subtracting(order).sorted()
        print("  * FAILED (\(order)\(missing.isEmpty ? "" : ", missing \(missing)"))")
        return false
      }
      let starts = delayEnqueueStarts.withLock { $0 }
      let returns = delayEnqueueReturns.withLock { $0 }
      let calls = delays.map { (delay: $0, start: starts[$0]!, returned: returns[$0]!) }
      if let failure = Self.slowEnqueue(calls, limit: enqueueLimit) {
        print("  * FAILED (\(failure))")
        return false
      }
      let runs = ranInOrder.map { run in
        let nominal = Duration.milliseconds(run.delay) as! C.Duration
        return ScheduledRun(
          delay: run.delay,
          earliestDeadline: starts[run.delay]!.advanced(by: nominal),
          latestDeadline: returns[run.delay]!.advanced(by: nominal),
          enqueueReturned: returns[run.delay]!,
          ran: run.ran
        )
      }
      if let violation = Self.orderViolation(runs, slack: slack) {
        print("  * FAILED (\(order): \(violation))")
        return false
      }
      for (delay, ran) in ranInOrder.sorted(by: { $0.delay < $1.delay }) {
        let actualDelay = starts[delay]!.duration(to: ran) as! Duration

        // Must not return before the requested delay
        let minDelay: Duration = .milliseconds(delay)

        // Warn if we return more than 25% after the requested delay
        let warnDelay: Duration = .milliseconds(delay + delay / 4)

        // Must not return more than 25% after the requested delay
        let maxDelay: Duration = .milliseconds(
          delay
            + max(
              delay / 4,
              maxDelayTolerance
            )
        )

        if actualDelay < minDelay
          && minDelay - actualDelay > .milliseconds(minDelayTolerance)
        {
          print("  * FAILED (\(actualDelay) < \(minDelay))")
          return false
        }

        if actualDelay > maxDelay {
          print("  * FAILED (\(actualDelay) > \(maxDelay))")
          return false
        }

        if actualDelay > warnDelay {
          print("  * WARNING (\(actualDelay) > \(warnDelay))")
        }
      }
      print("  * OK")
      return true
    }

    print("  - Timestamps")
    let baseTime = clock.now
    let targets = delays.map {
      baseTime.advanced(by: Duration.milliseconds($0) as! C.Duration)
    }
    // The jobs, by index into `targets`, in the order they ran, and when each ran.
    let targetedRuns = Mutex<[(ndx: Int, ran: C.Instant)]>([])
    // A pause in the enqueuing loop can let a target pass before its job is
    // enqueued. The executor may order such a job by its target, or run it only
    // after jobs it already took, but no later than once `enqueue` returns, so
    // the checks bound its deadline by the target and that return.
    let targetEnqueueStarts = Mutex<[Int: C.Instant]>([:])
    let targetEnqueueReturns = Mutex<[Int: C.Instant]>([:])

    await withCheckedContinuation { continuation in
      let runLoopExecutor = schedulingExecutor as? (any RunLoopExecutor)

      for (ndx, target) in targets.enumerated().reversed() {
        let job = createJob(priority: .medium) {
          let actualTime = clock.now
          print("    + Targeted job (target \(target), actual \(actualTime))")
          targetedRuns.withLock {
            $0.append((ndx, actualTime))
          }
        }
        targetEnqueueStarts.withLock {
          $0[ndx] = clock.now
        }
        schedulingExecutor.enqueue(
          job,
          at: target,
          clock: clock
        )
        targetEnqueueReturns.withLock {
          $0[ndx] = clock.now
        }
      }
      let stopJob = createJob(priority: .low) {
        print("    + Stopping")
        if let runLoopExecutor {
          print("    + Telling RunLoopExecutor to stop")
          runLoopExecutor.stop()
        }
        continuation.resume()
      }
      let stopDelay = Duration.milliseconds(1100) as! C.Duration
      schedulingExecutor.enqueue(
        stopJob,
        after: stopDelay,
        clock: clock
      )
      if let runLoopExecutor {
        print("    + Telling RunLoopExecutor to run")
        try! runLoopExecutor.run()
      }
    }

    let result2 = targetedRuns.withLock { ranInOrder in
      let order = ranInOrder.map { delays[$0.ndx] }
      if order.sorted() != delays {
        let missing = Set(delays).subtracting(order).sorted()
        print("  * FAILED (\(order)\(missing.isEmpty ? "" : ", missing \(missing)"))")
        return false
      }
      let starts = targetEnqueueStarts.withLock { $0 }
      let returns = targetEnqueueReturns.withLock { $0 }
      let calls = targets.indices.map { (delay: delays[$0], start: starts[$0]!, returned: returns[$0]!) }
      if let failure = Self.slowEnqueue(calls, limit: enqueueLimit) {
        print("  * FAILED (\(failure))")
        return false
      }
      let runs = ranInOrder.map { run in
        ScheduledRun(
          delay: delays[run.ndx],
          earliestDeadline: targets[run.ndx],
          latestDeadline: max(targets[run.ndx], returns[run.ndx]!),
          enqueueReturned: returns[run.ndx]!,
          ran: run.ran
        )
      }
      if let violation = Self.orderViolation(runs, slack: slack) {
        print("  * FAILED (\(order): \(violation))")
        return false
      }
      for (ndx, actualTime) in ranInOrder.sorted(by: { $0.ndx < $1.ndx }) {
        let target = targets[ndx]
        // A job enqueued after its target is due once the executor has it, which
        // is no later than when `enqueue` returns.
        let deadline = max(target, returns[ndx]!)

        // Must not return before the requested time
        let minTime = target

        // Warn if we return more than 25% after the requested time
        let warnTime = deadline.advanced(
          by: Duration.milliseconds(delays[ndx] / 4) as! C.Duration
        )

        // Must not return more than 25% after the requested time
        let maxTime = deadline.advanced(
          by: Duration.milliseconds(
            max(
              delays[ndx] / 4,
              maxDelayTolerance
            )
          ) as! C.Duration
        )

        if actualTime < minTime
          && (actualTime.duration(to: minTime) as! Duration)
            > .milliseconds(minDelayTolerance)
        {
          print("  * FAILED (\(actualTime) < \(minTime))")
          return false
        }

        if actualTime > maxTime {
          print("  * FAILED (\(actualTime) > \(maxTime), target \(target))")
          return false
        }

        if actualTime > warnTime {
          print("  * WARNING (\(actualTime) > \(warnTime), target \(target))")
        }
      }
      print("  * OK")
      return true
    }

    return result && result2
  }
  static func test(schedulingExecutor: some SchedulingExecutor) async -> Bool {
    let result = await test(
      schedulingExecutor: schedulingExecutor,
      clock: .suspending
    )
    let result2 = await test(
      schedulingExecutor: schedulingExecutor,
      clock: .continuous
    )
    return result && result2
  }

  static func test(taskExecutor: some TaskExecutor) async -> Bool {
    print("\no TaskExecutor")

    let counter = Mutex<Int>(30)

    await withCheckedContinuation { continuation in
      let runLoopExecutor = taskExecutor as? (any RunLoopExecutor)

      for _ in 0..<10 {
        let highJob = createJob(priority: .high) {
          print("  - High priority job")
          counter.withLock {
            $0 = $0 - 1
            if $0 == 0 {
              if let runLoopExecutor {
                print("  - Telling RunLoopExecutor to stop")
                runLoopExecutor.stop()
              }
              continuation.resume()
            }
          }
        }
        let mediumJob = createJob(priority: .medium) {
          print("  - Medium priority job")
          counter.withLock {
            $0 = $0 - 1
            if $0 == 0 {
              if let runLoopExecutor {
                print("  - Telling RunLoopExecutor to stop")
                runLoopExecutor.stop()
              }
              continuation.resume()
            }
          }
        }
        let lowJob = createJob(priority: .low) {
          print("  - Low priority job")
          counter.withLock {
            $0 = $0 - 1
            if $0 == 0 {
              if let runLoopExecutor {
                print("  - Telling RunLoopExecutor to stop")
                runLoopExecutor.stop()
              }
              continuation.resume()
            }
          }
        }

        taskExecutor.enqueue(highJob)
        taskExecutor.enqueue(mediumJob)
        taskExecutor.enqueue(lowJob)
      }

      if let runLoopExecutor {
        print("  - Telling RunLoopExecutor to run")
        try! runLoopExecutor.run()
      }
    }

    print("  * OK")

    return true
  }
}
