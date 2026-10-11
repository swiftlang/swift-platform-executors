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

import BasicContainers
import Benchmark
import PlatformExecutors

/// Connects to and accepts loopback TCP connections.
///
/// - Parameters:
///   - numberOfConnections: The number of connections to connect and accept.
///   - ioBackend: The I/O backend that the executor's threads use.
///   - benchmark: The benchmark to measure.
@available(anyAppleOS 27.0, *)
func runTCPConnect(numberOfConnections: Int, ioBackend: PThreadIOBackend, benchmark: Benchmark) async throws {
  try await PThreadTaskExecutor.withExecutor(name: "TCPConnect", poolSize: 1, ioBackend: ioBackend) { executor in
    try await withTaskExecutorPreference(executor) {
      let listener = try await TCPListener.bind(
        to: .v4(SocketAddress.V4(address: .loopback, port: 0)),
        backlog: numberOfConnections
      )
      let address = try listener.localAddress

      // The capacity is reserved before the measurement
      // so that appending the connections does not allocate.
      var connections = UniqueArray<TCPConnection>(minimumCapacity: 2 * numberOfConnections)

      benchmark.startMeasurement()
      for _ in 0..<numberOfConnections {
        connections.append(try await TCPConnection.connect(to: address))
        connections.append(try await listener.accept())
      }
      benchmark.stopMeasurement()

      while let connection = connections.popLast() {
        try await connection.close()
      }
      try await listener.close()
    }
  }
}
