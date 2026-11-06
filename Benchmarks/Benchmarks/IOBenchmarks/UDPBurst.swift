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

/// The size of every datagram.
private let datagramSize = 512

/// The number of datagrams that the client sends before it waits for the server to acknowledge them.
private let burstSize = 32

/// Sends bursts of datagrams from a client to a server over the loopback interface.
///
/// - Parameters:
///   - numberOfBursts: The number of bursts that the client sends.
///   - ioBackend: The I/O backend that the executor's threads use.
///   - benchmark: The benchmark to measure.
@available(anyAppleOS 27.0, *)
func runUDPBurst(numberOfBursts: Int, ioBackend: PThreadIOBackend, benchmark: Benchmark) async throws {
  try await PThreadTaskExecutor.withExecutor(name: "UDPBurst", poolSize: 1, ioBackend: ioBackend) { executor in
    try await withTaskExecutorPreference(executor) {
      benchmark.startMeasurement()
      defer {
        benchmark.stopMeasurement()
      }

      try await withThrowingTaskGroup { group in
        var server = try await UDPSocket.bind(to: .v4(SocketAddress.V4(address: .loopback, port: 0)))
        let address = try server.localAddress
        group.addTask {
          try await runClient(connectingTo: address, numberOfBursts: numberOfBursts)
        }

        try await runServer(socket: &server, numberOfBursts: numberOfBursts)
        try await server.close()

        try await group.waitForAll()
      }
    }
  }
}

@available(anyAppleOS 27.0, *)
private func runClient(connectingTo address: SocketAddress, numberOfBursts: Int) async throws {
  var connection = try await UDPConnection.connect(to: address)

  let datagram = [UInt8](repeating: 0, count: datagramSize)
  let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: datagramSize, alignment: 1)
  defer {
    buffer.deallocate()
  }

  for _ in 0..<numberOfBursts {
    for _ in 0..<burstSize {
      try await connection.write(from: datagram.span.bytes)
    }
    var output = OutputRawSpan(buffer: buffer, initializedCount: 0)
    try await connection.read(into: &output)
    _ = output.finalize(for: buffer)
  }

  try await connection.close()
}

@available(anyAppleOS 27.0, *)
private func runServer(socket: inout UDPSocket, numberOfBursts: Int) async throws {
  let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: datagramSize, alignment: 1)
  defer {
    buffer.deallocate()
  }

  for _ in 0..<numberOfBursts {
    var sender: SocketAddress?
    for _ in 0..<burstSize {
      var output = OutputRawSpan(buffer: buffer, initializedCount: 0)
      sender = try await socket.receive(into: &output).sender
      _ = output.finalize(for: buffer)
    }
    try await socket.send(from: RawSpan(_unsafeBytes: UnsafeRawBufferPointer(rebasing: buffer[..<1])), to: sender!)
  }
}
