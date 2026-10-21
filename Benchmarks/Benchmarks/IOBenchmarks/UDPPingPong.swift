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

/// The size of every datagram that the client sends and the server sends back.
private let datagramSize = 512

/// Plays ping pong between a connected client and a bound server socket over the loopback interface.
///
/// - Parameters:
///   - numberOfDatagrams: The number of datagrams that go back and forth.
///   - ioBackend: The I/O backend that the executor's threads use.
///   - benchmark: The benchmark to measure.
@available(anyAppleOS 27.0, *)
func runUDPPingPong(numberOfDatagrams: Int, ioBackend: PThreadIOBackend, benchmark: Benchmark) async throws {
  try await PThreadTaskExecutor.withExecutor(name: "UDPPingPong", poolSize: 1, ioBackend: ioBackend) { executor in
    try await withTaskExecutorPreference(executor) {
      benchmark.startMeasurement()
      defer {
        benchmark.stopMeasurement()
      }

      try await withThrowingTaskGroup { group in
        var server = try await UDPSocket.bind(to: .v4(SocketAddress.V4(address: .loopback, port: 0)))
        let address = try server.localAddress
        group.addTask {
          try await runClient(connectingTo: address, numberOfDatagrams: numberOfDatagrams)
        }

        try await runServer(socket: &server, numberOfDatagrams: numberOfDatagrams)
        try await server.close()

        try await group.waitForAll()
      }
    }
  }
}

/// Sends the datagrams and waits for each one to come back before sending the next one.
@available(anyAppleOS 27.0, *)
private func runClient(connectingTo address: SocketAddress, numberOfDatagrams: Int) async throws {
  var connection = try await UDPConnection.connect(to: address)

  let datagram = [UInt8](repeating: 0, count: datagramSize)
  // The buffer has to stay alive while a read is in flight so we heap alloc here.
  let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: datagramSize, alignment: 1)
  defer {
    buffer.deallocate()
  }

  for _ in 0..<numberOfDatagrams {
    try await connection.write(from: datagram.span.bytes)

    var output = OutputRawSpan(buffer: buffer, initializedCount: 0)
    try await connection.read(into: &output)
    _ = output.finalize(for: buffer)
  }

  try await connection.close()
}

/// Sends every datagram back to its sender.
@available(anyAppleOS 27.0, *)
private func runServer(socket: inout UDPSocket, numberOfDatagrams: Int) async throws {
  // The buffer has to stay alive while a receive is in flight so we heap alloc here.
  let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: datagramSize, alignment: 1)
  defer {
    buffer.deallocate()
  }

  for _ in 0..<numberOfDatagrams {
    var output = OutputRawSpan(buffer: buffer, initializedCount: 0)
    let (count, sender) = try await socket.receive(into: &output)
    _ = output.finalize(for: buffer)
    try await socket.send(
      from: RawSpan(_unsafeBytes: UnsafeRawBufferPointer(rebasing: buffer[..<count])),
      to: sender
    )
  }
}
