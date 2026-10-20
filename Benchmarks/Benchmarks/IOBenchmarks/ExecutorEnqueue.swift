//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Benchmark
import PlatformExecutors

/// Runs tasks that yield again and again on an executor.
///
/// - Parameters:
///   - tasks: The number of tasks, which is also the number of jobs in the queue.
///   - yieldsPerTask: The number of times that every task yields.
///   - benchmark: The benchmark to measure.
@available(anyAppleOS 27.0, *)
func runYieldingTasks(tasks: Int, yieldsPerTask: Int, benchmark: Benchmark) async {
  await PThreadTaskExecutor.withExecutor(name: "ExecutorEnqueue", poolSize: 1) { executor in
    await withTaskExecutorPreference(executor) {
      benchmark.startMeasurement()
      defer {
        benchmark.stopMeasurement()
      }

      await withTaskGroup { group in
        for _ in 0..<tasks {
          group.addTask {
            for _ in 0..<yieldsPerTask {
              await Task.yield()
            }
          }
        }
        await group.waitForAll()
      }
    }
  }
}

/// Spawns tasks that do nothing on an executor enqueued from another executor.
///
/// - Parameters:
///   - tasks: The number of tasks to spawn.
///   - benchmark: The benchmark to measure.
@available(anyAppleOS 27.0, *)
func runSpawningTasks(tasks: Int, benchmark: Benchmark) async {
  await PThreadTaskExecutor.withExecutor(name: "ExecutorEnqueue", poolSize: 1) { executor in
    benchmark.startMeasurement()
    defer {
      benchmark.stopMeasurement()
    }

    await withTaskGroup { group in
      for _ in 0..<tasks {
        group.addTask(executorPreference: executor) {}
      }
      await group.waitForAll()
    }
  }
}
