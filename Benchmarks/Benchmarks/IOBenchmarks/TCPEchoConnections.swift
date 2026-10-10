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

/// The size of every message that the clients send.
private let messageSize = 10_000

/// The size of the buffers that the clients and the server read into.
private let readBufferSize = 64 * 1024

/// Echoes messages over many loopback TCP connections at the same time.
///
/// - Parameters:
///   - connections: The number of connections.
///   - messagesPerConnection: The number of messages that every client writes.
///   - benchmark: The benchmark to measure.
@available(anyAppleOS 27.0, *)
func runTCPEcho(connections: Int, messagesPerConnection: Int, benchmark: Benchmark) async throws {
  try await PThreadTaskExecutor.withExecutor(name: "TCPEchoConnections", poolSize: 1) { executor in
    try await withTaskExecutorPreference(executor) {
      benchmark.startMeasurement()
      defer {
        benchmark.stopMeasurement()
      }

      let listener = try await TCPListener.bind(to: .v4(SocketAddress.V4(address: .loopback, port: 0)))
      let address = try listener.localAddress

      try await withThrowingTaskGroup { group in
        for _ in 0..<connections {
          let client = try await TCPConnection.connect(to: address)
          let server = try await listener.accept()

          // A noncopyable value cannot be consumed out of a closure capture, so the
          // connections are moved into the child tasks through optionals.
          var clientBox: TCPConnection? = consume client
          var serverBox: TCPConnection? = consume server
          group.addTask {
            let client = clientBox.take()!
            try await runEchoClient(on: client, numberOfMessages: messagesPerConnection)
            try await client.close()
          }
          group.addTask {
            var server = serverBox.take()!
            try await runEchoServer(on: &server)
            try await server.close()
          }
        }
        try await group.waitForAll()
      }

      try await listener.close()
    }
  }
}

/// Writes the messages while concurrently reading their echoes.
@available(anyAppleOS 27.0, *)
private func runEchoClient(on connection: borrowing TCPConnection, numberOfMessages: Int) async throws {
  try await connection.withSplit { readHalf, writeHalf in
    _ = try await withConcurrently {
      // The buffer has to stay alive while a read is in flight so we heap alloc here.
      let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: readBufferSize, alignment: 1)
      defer {
        buffer.deallocate()
      }

      var remaining = numberOfMessages * messageSize
      while remaining > 0 {
        var output = OutputRawSpan(buffer: buffer, initializedCount: 0)
        let count = try await readHalf.read(into: &output)
        _ = output.finalize(for: buffer)
        if count == 0 {
          throw EchoError.unexpectedEndOfStream
        }
        remaining -= count
      }
    } _: {
      let message = [UInt8](repeating: 0, count: messageSize)
      for _ in 0..<numberOfMessages {
        try await writeHalf.write(from: message.span.bytes)
      }
      try await writeHalf.shutdown()
    }
  }
}

/// Echoes everything the client sends until the client closes the connection.
@available(anyAppleOS 27.0, *)
private func runEchoServer(on connection: inout TCPConnection) async throws {
  // The buffer has to stay alive while a read is in flight so we heap alloc here.
  let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: readBufferSize, alignment: 1)
  defer {
    buffer.deallocate()
  }

  while true {
    var output = OutputRawSpan(buffer: buffer, initializedCount: 0)
    let count = try await connection.read(into: &output)
    _ = output.finalize(for: buffer)
    if count == 0 {
      return
    }
    try await connection.write(from: RawSpan(_unsafeBytes: UnsafeRawBufferPointer(rebasing: buffer[..<count])))
  }
}

private enum EchoError: Error {
  /// The peer closed the connection before all echoes arrived.
  case unexpectedEndOfStream
}
