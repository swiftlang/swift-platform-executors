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

/// The size of every message that the client sends.
private let messageSize = 10_000

/// Echoes messages between a client and a server connection over the loopback interface.
///
/// - Parameters:
///   - numberOfMessages: The number of messages that the client writes.
///   - benchmark: The benchmark to measure.
@available(anyAppleOS 27.0, *)
func runTCPEcho(numberOfMessages: Int, benchmark: Benchmark) async throws {
  try await PThreadTaskExecutor.withExecutor(name: "TCPEcho", poolSize: 1) { executor in
    try await withTaskExecutorPreference(executor) {
      benchmark.startMeasurement()
      defer {
        benchmark.stopMeasurement()
      }

      let listener = try await TCPListener.bind(to: .v4(SocketAddress.V4(address: .loopback, port: 0)))
      let address = try listener.localAddress

      try await withThrowingTaskGroup { group in
        group.addTask {
          try await runEchoClient(connectingTo: address, numberOfMessages: numberOfMessages)
        }

        var connection = try await listener.accept()
        try await runEchoServer(on: &connection)
        try await connection.close()

        try await group.waitForAll()
      }

      try await listener.close()
    }
  }
}

/// Writes the messages while concurrently reading their echoes.
@available(anyAppleOS 27.0, *)
private func runEchoClient(connectingTo address: SocketAddress, numberOfMessages: Int) async throws {
  let connection = try await TCPConnection.connect(to: address)

  try await connection.withSplit { readHalf, writeHalf in
    _ = try await withConcurrently {
      // The buffer has to stay alive while a read is in flight so we heap alloc here.
      let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: messageSize, alignment: 1)
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

  try await connection.close()
}

/// Echoes everything the client sends until the client closes the connection.
@available(anyAppleOS 27.0, *)
private func runEchoServer(on connection: inout TCPConnection) async throws {
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

private enum EchoError: Error {
  /// The peer closed the connection before all echoes arrived.
  case unexpectedEndOfStream
}
