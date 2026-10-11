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

/// The size of every message that the client sends.
private let messageSize = 10_000

/// Echoes messages between a client and a server connection over the loopback interface.
///
/// - Parameters:
///   - numberOfMessages: The number of messages that the client writes.
///   - ioBackend: The I/O backend that the executor's threads use.
///   - benchmark: The benchmark to measure.
@available(anyAppleOS 27.0, *)
func runTCPEcho(numberOfMessages: Int, ioBackend: PThreadIOBackend, benchmark: Benchmark) async throws {
  var clientBuffers: EchoClientBuffers? = EchoClientBuffers()
  var serverBuffer = UniqueArray<UInt8>(minimumCapacity: messageSize)

  try await PThreadTaskExecutor.withExecutor(name: "TCPEcho", poolSize: 1, ioBackend: ioBackend) { executor in
    try await withTaskExecutorPreference(executor) {
      benchmark.startMeasurement()
      defer {
        benchmark.stopMeasurement()
      }

      let listener = try await TCPListener.bind(to: .v4(SocketAddress.V4(address: .loopback, port: 0)))
      let address = try listener.localAddress

      try await withThrowingTaskGroup { group in
        // A noncopyable value cannot be consumed out of a closure capture, so the
        // arrays are moved into the child task through an optional.
        var clientBuffersBox = clientBuffers.take()
        group.addTask {
          var buffers = clientBuffersBox.take()!
          try await runEchoClient(connectingTo: address, numberOfMessages: numberOfMessages, buffers: &buffers)
        }

        var connection = try await listener.accept()
        try await runEchoServer(on: &connection, buffer: &serverBuffer)
        try await connection.close()

        try await group.waitForAll()
      }

      try await listener.close()
    }
  }
}

/// The arrays that the client reads into and writes from.
@available(anyAppleOS 27.0, *)
private struct EchoClientBuffers: ~Copyable {
  /// The array that the client reads the echoes into.
  var readBuffer = UniqueArray<UInt8>(minimumCapacity: messageSize)

  /// The message that the client writes.
  var message = UniqueArray<UInt8>(repeating: 0, count: messageSize)
}

/// Writes the messages while concurrently reading their echoes.
@available(anyAppleOS 27.0, *)
private func runEchoClient(
  connectingTo address: SocketAddress,
  numberOfMessages: Int,
  buffers: inout EchoClientBuffers
) async throws {
  let connection = try await TCPConnection.connect(to: address)

  try await connection.withSplit { readHalf, writeHalf in
    _ = try await withConcurrently {
      var remaining = numberOfMessages * messageSize
      while remaining > 0 {
        buffers.readBuffer.removeAll()
        let count = try await buffers.readBuffer.append(addingByteCount: messageSize) { output in
          try await readHalf.read(into: &output)
        }
        if count == 0 {
          throw EchoError.unexpectedEndOfStream
        }
        remaining -= count
      }
    } _: { [message = buffers.message.span] in
      for _ in 0..<numberOfMessages {
        try await writeHalf.write(from: message.bytes)
      }
      try await writeHalf.shutdown()
    }
  }

  try await connection.close()
}

/// Echoes everything the client sends until the client closes the connection.
@available(anyAppleOS 27.0, *)
private func runEchoServer(on connection: inout TCPConnection, buffer: inout UniqueArray<UInt8>) async throws {
  while true {
    buffer.removeAll()
    let count = try await buffer.append(addingByteCount: messageSize) { output in
      try await connection.read(into: &output)
    }
    if count == 0 {
      return
    }
    try await connection.write(from: buffer.span.bytes)
  }
}

private enum EchoError: Error {
  /// The peer closed the connection before all echoes arrived.
  case unexpectedEndOfStream
}
