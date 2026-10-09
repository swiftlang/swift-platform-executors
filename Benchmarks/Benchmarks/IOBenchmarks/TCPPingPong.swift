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

/// The size of every message that the client sends and the server sends back.
private let messageSize = 10_000

/// Plays ping pong between a client and a server connection over the loopback interface.
///
/// - Parameters:
///   - numberOfMessages: The number of messages that go back and forth.
///   - benchmark: The benchmark to measure.
@available(anyAppleOS 27.0, *)
func runTCPPingPong(numberOfMessages: Int, benchmark: Benchmark) async throws {
  try await PThreadTaskExecutor.withExecutor(name: "TCPPingPong", poolSize: 1) { executor in
    try await withTaskExecutorPreference(executor) {
      benchmark.startMeasurement()
      defer {
        benchmark.stopMeasurement()
      }

      let listener = try await TCPListener.bind(to: .v4(SocketAddress.V4(address: .loopback, port: 0)))
      let address = try listener.localAddress

      try await withThrowingTaskGroup { group in
        group.addTask {
          try await runClient(connectingTo: address, numberOfMessages: numberOfMessages)
        }

        var connection = try await listener.accept()
        try await runServer(on: &connection)
        try await connection.close()

        try await group.waitForAll()
      }

      try await listener.close()
    }
  }
}

/// Sends the messages and waits for each one to come back before sending the next one.
@available(anyAppleOS 27.0, *)
private func runClient(connectingTo address: SocketAddress, numberOfMessages: Int) async throws {
  var connection = try await TCPConnection.connect(to: address)

  let message = [UInt8](repeating: 0, count: messageSize)
  // The buffer has to stay alive while a read is in flight so we heap alloc here.
  let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: messageSize, alignment: 1)
  defer {
    buffer.deallocate()
  }

  for _ in 0..<numberOfMessages {
    try await connection.write(from: message.span.bytes)

    var output = OutputRawSpan(buffer: buffer, initializedCount: 0)
    while output.freeCapacity > 0 {
      if try await connection.read(into: &output) == 0 {
        throw PingPongError.unexpectedEndOfStream
      }
    }
    _ = output.finalize(for: buffer)
  }

  try await connection.close()
}

/// Sends everything back that the client sends until the client closes the connection.
@available(anyAppleOS 27.0, *)
private func runServer(on connection: inout TCPConnection) async throws {
  // The buffer has to stay alive while a read is in flight so we heap alloc here.
  let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: messageSize, alignment: 1)
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

private enum PingPongError: Error {
  /// The peer closed the connection before a message came back completely.
  case unexpectedEndOfStream
}
