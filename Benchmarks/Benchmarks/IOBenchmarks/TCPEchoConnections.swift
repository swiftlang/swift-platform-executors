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

/// The size of every message that the clients send.
private let messageSize = 10_000

/// The size of the buffers that the clients and the servers read into.
private let readBufferSize = 64 * 1024

/// Echoes messages over many loopback TCP connections at the same time.
///
/// - Parameters:
///   - connections: The number of connections.
///   - messagesPerConnection: The number of messages that every client writes.
///   - ioBackend: The I/O backend that the executor's threads use.
///   - benchmark: The benchmark to measure.
@available(anyAppleOS 27.0, *)
func runTCPEcho(
  connections: Int,
  messagesPerConnection: Int,
  ioBackend: PThreadIOBackend,
  benchmark: Benchmark
) async throws {
  var buffers = UniqueArray<ConnectionBuffers>(minimumCapacity: connections)
  for _ in 0..<connections {
    buffers.append(ConnectionBuffers())
  }

  try await PThreadTaskExecutor.withExecutor(name: "TCPEchoConnections", poolSize: 1, ioBackend: ioBackend) {
    executor in
    try await withTaskExecutorPreference(executor) {
      benchmark.startMeasurement()
      defer {
        benchmark.stopMeasurement()
      }

      let listener = try await TCPListener.bind(to: .v4(SocketAddress.V4(address: .loopback, port: 0)))
      let address = try listener.localAddress

      try await withThrowingTaskGroup { group in
        for _ in 0..<connections {
          let connectionBuffers = buffers.removeLast()
          let client = EchoClient(
            connection: try await TCPConnection.connect(to: address),
            readBuffer: connectionBuffers.clientReadBuffer,
            message: connectionBuffers.message
          )
          let server = EchoServer(
            connection: try await listener.accept(),
            buffer: connectionBuffers.serverBuffer
          )

          // A noncopyable value cannot be consumed out of a closure capture, so the
          // connections and their arrays are moved into the child tasks through optionals.
          var clientBox: EchoClient? = consume client
          var serverBox: EchoServer? = consume server
          group.addTask {
            var client = clientBox.take()!
            try await runEchoClient(&client, numberOfMessages: messagesPerConnection)
            try await client.connection.close()
          }
          group.addTask {
            var server = serverBox.take()!
            try await runEchoServer(&server)
            try await server.connection.close()
          }
        }
        try await group.waitForAll()
      }

      try await listener.close()
    }
  }
}

/// The arrays that the tasks of one connection read into and write from, which are allocated before the
/// connection is set up.
@available(anyAppleOS 27.0, *)
private struct ConnectionBuffers: ~Copyable {
  /// The array that the client reads the echoes into.
  var clientReadBuffer = UniqueArray<UInt8>(minimumCapacity: readBufferSize)

  /// The message that the client writes.
  var message = UniqueArray<UInt8>(repeating: 0, count: messageSize)

  /// The array that the server reads into and writes back from.
  var serverBuffer = UniqueArray<UInt8>(minimumCapacity: readBufferSize)
}

/// What the client task of a connection owns.
@available(anyAppleOS 27.0, *)
private struct EchoClient: ~Copyable {
  /// The client's connection.
  var connection: TCPConnection

  /// The array that the client reads the echoes into.
  var readBuffer: UniqueArray<UInt8>

  /// The message that the client writes.
  var message: UniqueArray<UInt8>
}

/// What the server task of a connection owns.
@available(anyAppleOS 27.0, *)
private struct EchoServer: ~Copyable {
  /// The server's connection.
  var connection: TCPConnection

  /// The array that the server reads into and writes back from.
  var buffer: UniqueArray<UInt8>
}

/// Writes the messages while concurrently reading their echoes.
@available(anyAppleOS 27.0, *)
private func runEchoClient(_ client: inout EchoClient, numberOfMessages: Int) async throws {
  try await client.connection.withSplit { readHalf, writeHalf in
    _ = try await withConcurrently {
      var remaining = numberOfMessages * messageSize
      while remaining > 0 {
        client.readBuffer.removeAll()
        let count = try await client.readBuffer.append(addingByteCount: readBufferSize) { output in
          try await readHalf.read(into: &output)
        }
        if count == 0 {
          throw EchoError.unexpectedEndOfStream
        }
        remaining -= count
      }
    } _: { [message = client.message.span] in
      for _ in 0..<numberOfMessages {
        try await writeHalf.write(from: message.bytes)
      }
      try await writeHalf.shutdown()
    }
  }
}

/// Echoes everything the client sends until the client closes the connection.
@available(anyAppleOS 27.0, *)
private func runEchoServer(_ server: inout EchoServer) async throws {
  while true {
    server.buffer.removeAll()
    let count = try await server.buffer.append(addingByteCount: readBufferSize) { output in
      try await server.connection.read(into: &output)
    }
    if count == 0 {
      return
    }
    try await server.connection.write(from: server.buffer.span.bytes)
  }
}

private enum EchoError: Error {
  /// The peer closed the connection before all echoes arrived.
  case unexpectedEndOfStream
}
