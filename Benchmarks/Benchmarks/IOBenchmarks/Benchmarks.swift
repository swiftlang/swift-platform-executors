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

/// The I/O backends that the benchmarks run on.
let ioBackends: [PThreadIOBackend] = {
  #if canImport(Darwin)
  let candidates: [PThreadIOBackend] = [.kqueue]
  #elseif canImport(Glibc)
  let candidates: [PThreadIOBackend] = [.epoll, .ioUring]
  #else
  let candidates: [PThreadIOBackend] = [.platformDefault]
  #endif
  let backends = candidates.filter { ioBackend in
    do {
      try ioBackend.checkAvailability()
      return true
    } catch {
      print("The benchmarks skip the \(ioBackend) backend, which is not available: \(error)")
      return false
    }
  }
  print("The benchmarks run on the I/O backends: \(backends)")
  return backends
}()

/// Registers a benchmark once for every backend in ``ioBackends``.
func ioBenchmark(
  _ name: String,
  configuration: Benchmark.Configuration,
  closure: @escaping @Sendable (Benchmark, PThreadIOBackend) async throws -> Void
) {
  for ioBackend in ioBackends {
    Benchmark("\(name) (\(ioBackend))", configuration: configuration) { benchmark in
      try await closure(benchmark, ioBackend)
    }
  }
}

let benchmarks: @Sendable () -> Void = {
  let defaultMetrics: [BenchmarkMetric] = [
    .mallocCountTotal,
    .instructions,
    .contextSwitches,
    .wallClock,
  ]

  ioBenchmark(
    "TCPPingPong",
    configuration: .init(
      metrics: defaultMetrics,
      scalingFactor: .kilo,
      maxDuration: .seconds(10_000_000),
      maxIterations: 5
    )
  ) { benchmark, ioBackend in
    guard #available(anyAppleOS 27.0, *) else {
      fatalError("The TCP ping pong benchmark requires the I/O APIs.")
    }
    try await runTCPPingPong(
      numberOfMessages: benchmark.scaledIterations.upperBound,
      ioBackend: ioBackend,
      benchmark: benchmark
    )
  }

  ioBenchmark(
    "TCPEcho",
    configuration: .init(
      metrics: defaultMetrics,
      scalingFactor: .kilo,
      maxDuration: .seconds(10_000_000),
      maxIterations: 5
    )
  ) { benchmark, ioBackend in
    guard #available(anyAppleOS 27.0, *) else {
      fatalError("The TCP echo benchmark requires the I/O APIs.")
    }
    try await runTCPEcho(
      numberOfMessages: benchmark.scaledIterations.upperBound,
      ioBackend: ioBackend,
      benchmark: benchmark
    )
  }

  ioBenchmark(
    "TCPConnect",
    configuration: .init(
      metrics: defaultMetrics,
      scalingFactor: .kilo,
      maxDuration: .seconds(10_000_000),
      maxIterations: 5
    )
  ) { benchmark, ioBackend in
    guard #available(anyAppleOS 27.0, *) else {
      fatalError("The TCP connect benchmark requires the I/O APIs.")
    }
    try await runTCPConnect(
      numberOfConnections: benchmark.scaledIterations.upperBound,
      ioBackend: ioBackend,
      benchmark: benchmark
    )
  }

  for connections in [10, 100, 1000] {
    ioBenchmark(
      "TCPEcho\(connections)Connections",
      configuration: .init(
        metrics: defaultMetrics,
        scalingFactor: .one,
        maxDuration: .seconds(10_000_000),
        maxIterations: 5
      )
    ) { benchmark, ioBackend in
      guard #available(anyAppleOS 27.0, *) else {
        fatalError("The TCP echo benchmark requires the I/O APIs.")
      }
      try await runTCPEcho(
        connections: connections,
        messagesPerConnection: 100,
        ioBackend: ioBackend,
        benchmark: benchmark
      )
    }
  }
}
