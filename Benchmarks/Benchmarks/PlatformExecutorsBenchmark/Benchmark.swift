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

import Benchmark
import PlatformExecutors

nonisolated(unsafe) let benchmarks = {
  let defaultMetrics: [BenchmarkMetric] = [
    .mallocCountTotal
  ]

  Benchmark(
    "PThreadExecutor",
    configuration: .init(
      metrics: defaultMetrics,
      //      scalingFactor: .kilo,
      //      maxDuration: .seconds(10),
      //      maxIterations: 2
    )
  ) { benchmark in
    //    let executor = PThreadExecutor(name: "Benchmark")

    print("Executing benchmark")
    //    await withTaskExecutorPreference(executor) {
    //      benchmark.startMeasurement()
    //      defer {
    //        benchmark.stopMeasurement()
    //      }
    //      for _ in benchmark.scaledIterations {
    //        await Task.yield()
    //      }
    //    }
  }
}
