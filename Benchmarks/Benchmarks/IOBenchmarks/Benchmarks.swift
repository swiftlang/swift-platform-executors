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

  for tasks in [1, 100, 10_000] {
    Benchmark(
      "ExecutorEnqueueYield\(tasks)Tasks",
      configuration: .init(
        metrics: defaultMetrics,
        scalingFactor: .one,
        maxDuration: .seconds(10_000_000),
        maxIterations: 5
      )
    ) { benchmark in
      guard #available(anyAppleOS 27.0, *) else {
        fatalError("The executor enqueue benchmark requires the I/O APIs.")
      }
      await runYieldingTasks(tasks: tasks, yieldsPerTask: 1_000_000 / tasks, benchmark: benchmark)
    }
  }

  Benchmark(
    "ExecutorEnqueueSpawn100000Tasks",
    configuration: .init(
      metrics: defaultMetrics,
      scalingFactor: .one,
      maxDuration: .seconds(10_000_000),
      maxIterations: 5
    )
  ) { benchmark in
    guard #available(anyAppleOS 27.0, *) else {
      fatalError("The executor enqueue benchmark requires the I/O APIs.")
    }
    await runSpawningTasks(tasks: 100_000, benchmark: benchmark)
  }

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

  for (connections, idleConnections, poolSize) in [(100, 0, 1), (1000, 0, 1), (1000, 0, 4), (100, 1000, 1)] {
    var name = "TCPRequestResponse\(connections)\(idleConnections > 0 ? "Active\(idleConnections)Idle" : "")Connections"
    if poolSize > 1 {
      name += "PoolSize\(poolSize)"
    }
    ioBenchmark(
      name,
      configuration: .init(
        metrics: defaultMetrics,
        scalingFactor: .one,
        maxDuration: .seconds(10_000_000),
        maxIterations: 5
      )
    ) { benchmark, ioBackend in
      guard #available(anyAppleOS 27.0, *) else {
        fatalError("The TCP request response benchmark requires the I/O APIs.")
      }
      try await runTCPRequestResponse(
        connections: connections,
        idleConnections: idleConnections,
        requestsPerConnection: 100,
        poolSize: poolSize,
        ioBackend: ioBackend,
        benchmark: benchmark
      )
    }
  }

  for poolSize in [1, 4] {
    ioBenchmark(
      poolSize > 1 ? "TCPStreamPoolSize\(poolSize)" : "TCPStream",
      configuration: .init(
        metrics: defaultMetrics,
        scalingFactor: .kilo,
        maxDuration: .seconds(10_000_000),
        maxIterations: 5
      )
    ) { benchmark, ioBackend in
      guard #available(anyAppleOS 27.0, *) else {
        fatalError("The TCP stream benchmark requires the I/O APIs.")
      }
      try await runTCPStream(
        numberOfChunks: benchmark.scaledIterations.upperBound,
        poolSize: poolSize,
        ioBackend: ioBackend,
        benchmark: benchmark
      )
    }
  }

  ioBenchmark(
    "FileSequentialWrite",
    configuration: .init(
      metrics: defaultMetrics,
      scalingFactor: .kilo,
      maxDuration: .seconds(10_000_000),
      maxIterations: 5
    )
  ) { benchmark, ioBackend in
    guard #available(anyAppleOS 27.0, *) else {
      fatalError("The file sequential write benchmark requires the I/O APIs.")
    }
    try await runFileSequentialWrite(
      numberOfChunks: benchmark.scaledIterations.upperBound,
      ioBackend: ioBackend,
      benchmark: benchmark
    )
  }

  ioBenchmark(
    "FileSequentialRead",
    configuration: .init(
      metrics: defaultMetrics,
      scalingFactor: .kilo,
      maxDuration: .seconds(10_000_000),
      maxIterations: 5
    )
  ) { benchmark, ioBackend in
    guard #available(anyAppleOS 27.0, *) else {
      fatalError("The file sequential read benchmark requires the I/O APIs.")
    }
    try await runFileSequentialRead(
      numberOfChunks: benchmark.scaledIterations.upperBound,
      ioBackend: ioBackend,
      benchmark: benchmark
    )
  }

  ioBenchmark(
    "FileSmallReads",
    configuration: .init(
      metrics: defaultMetrics,
      scalingFactor: .kilo,
      maxDuration: .seconds(10_000_000),
      maxIterations: 5
    )
  ) { benchmark, ioBackend in
    guard #available(anyAppleOS 27.0, *) else {
      fatalError("The file small reads benchmark requires the I/O APIs.")
    }
    try await runFileSmallReads(
      numberOfReads: benchmark.scaledIterations.upperBound,
      ioBackend: ioBackend,
      benchmark: benchmark
    )
  }

  ioBenchmark(
    "FileOpenClose",
    configuration: .init(
      metrics: defaultMetrics,
      scalingFactor: .kilo,
      maxDuration: .seconds(10_000_000),
      maxIterations: 5
    )
  ) { benchmark, ioBackend in
    guard #available(anyAppleOS 27.0, *) else {
      fatalError("The file open and close benchmark requires the I/O APIs.")
    }
    try await runFileOpenClose(
      numberOfFiles: benchmark.scaledIterations.upperBound,
      ioBackend: ioBackend,
      benchmark: benchmark
    )
  }

  for (tasks, blockingPoolSize, poolSize) in [(16, 4, 1), (256, 4, 1), (256, 16, 1), (256, 4, 4), (256, 9, 9)] {
    ioBenchmark(
      "FileConcurrentReads\(tasks)TasksBlockingPoolSize\(blockingPoolSize)\(poolSize > 1 ? "PoolSize\(poolSize)" : "")",
      configuration: .init(
        metrics: defaultMetrics,
        scalingFactor: .one,
        maxDuration: .seconds(10_000_000),
        maxIterations: 5
      )
    ) { benchmark, ioBackend in
      guard #available(anyAppleOS 27.0, *) else {
        fatalError("The file benchmarks require the I/O APIs.")
      }
      try await runFileConcurrentReads(
        tasks: tasks,
        readsPerTask: 100,
        poolSize: poolSize,
        blockingPoolSize: blockingPoolSize,
        ioBackend: ioBackend,
        benchmark: benchmark
      )
    }
  }
}
