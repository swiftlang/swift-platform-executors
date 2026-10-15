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

/// The size of every write of the client and of the buffer that the server reads into.
private let chunkSize = 64 * 1024

/// Streams bytes from a client to a server connection over the loopback
/// interface.
///
/// The client writes as fast as it can and the server reads and discards
/// everything, so the writes wait whenever the socket buffers are full and the
/// reads whenever they are empty. Unlike in the echo benchmarks, operations
/// really have to wait here.
///
/// - Parameters:
///   - numberOfChunks: The number of chunks that the client writes.
///   - poolSize: The number of threads of the `PThreadTaskExecutor` that everything runs on.
///   - ioBackend: The I/O backend that the executor's threads use.
///   - benchmark: The benchmark to measure.
@available(anyAppleOS 27.0, *)
func runTCPStream(
  numberOfChunks: Int,
  poolSize: Int = 1,
  ioBackend: PThreadIOBackend,
  benchmark: Benchmark
) async throws {
  var chunk: UniqueArray<UInt8>? = UniqueArray(repeating: 0, count: chunkSize)
  var serverBuffer = UniqueArray<UInt8>(minimumCapacity: chunkSize)

  try await PThreadTaskExecutor.withExecutor(name: "TCPStream", poolSize: poolSize, ioBackend: ioBackend) { executor in
    try await withTaskExecutorPreference(executor) {
      benchmark.startMeasurement()
      defer {
        benchmark.stopMeasurement()
      }

      let listener = try await TCPListener.bind(to: .v4(SocketAddress.V4(address: .loopback, port: 0)))
      let address = try listener.localAddress

      try await withThrowingTaskGroup { group in
        // A noncopyable value cannot be consumed out of a closure capture, so the
        // chunk is moved into the child task through an optional.
        var chunkBox = chunk.take()
        group.addTask {
          let chunk = chunkBox.take()!
          var connection = try await TCPConnection.connect(to: address)
          for _ in 0..<numberOfChunks {
            try await connection.write(from: chunk.span.bytes)
          }
          try await connection.close()
        }

        var connection = try await listener.accept()
        var remaining = numberOfChunks * chunkSize
        while remaining > 0 {
          serverBuffer.removeAll()
          let count = try await serverBuffer.append(addingByteCount: chunkSize) { output in
            try await connection.read(into: &output)
          }
          if count == 0 {
            throw StreamError.unexpectedEndOfStream
          }
          remaining -= count
        }
        try await connection.close()

        try await group.waitForAll()
      }

      try await listener.close()
    }
  }
}

private enum StreamError: Error {
  /// The client closed the connection before all bytes arrived.
  case unexpectedEndOfStream
}
