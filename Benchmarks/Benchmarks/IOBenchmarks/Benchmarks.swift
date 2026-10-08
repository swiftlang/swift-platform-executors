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

let benchmarks: @Sendable () -> Void = {
  let defaultMetrics: [BenchmarkMetric] = [
    .mallocCountTotal,
    .instructions,
    .contextSwitches,
    .wallClock,
  ]

  Benchmark(
    "TCPPingPong",
    configuration: .init(
      metrics: defaultMetrics,
      scalingFactor: .kilo,
      maxDuration: .seconds(10_000_000),
      maxIterations: 5
    )
  ) { benchmark in
    guard #available(anyAppleOS 27.0, *) else {
      fatalError("The TCP ping pong benchmark requires the I/O APIs.")
    }
    try await runTCPPingPong(
      numberOfMessages: benchmark.scaledIterations.upperBound,
      benchmark: benchmark
    )
  }

  Benchmark(
    "TCPEcho",
    configuration: .init(
      metrics: defaultMetrics,
      scalingFactor: .kilo,
      maxDuration: .seconds(10_000_000),
      maxIterations: 5
    )
  ) { benchmark in
    guard #available(anyAppleOS 27.0, *) else {
      fatalError("The TCP echo benchmark requires the I/O APIs.")
    }
    try await runTCPEcho(
      numberOfMessages: benchmark.scaledIterations.upperBound,
      benchmark: benchmark
    )
  }
}
