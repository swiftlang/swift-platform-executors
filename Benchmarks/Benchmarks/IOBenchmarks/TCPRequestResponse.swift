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

/// The size of every request and every response.
private let messageSize = 256

/// Sends small requests and their responses over many loopback TCP connections
/// at the same time.
///
/// Every client sends a request and waits for its response before it sends the
/// next one, so every connection has at most one message in flight, while all
/// the connections together have many. This is where a mechanism that submits
/// and reaps many operations with one call can pay off.
///
/// Next to the active connections, there can be idle ones whose servers wait in
/// a read for the whole measurement, like the connections of a server that
/// mostly wait for their next request. They are set up before the measurement
/// starts and torn down after it ends.
///
/// - Parameters:
///   - connections: The number of active connections.
///   - idleConnections: The number of idle connections.
///   - requestsPerConnection: The number of requests that every client sends.
///   - poolSize: The number of threads of the `PThreadTaskExecutor` that everything runs on.
///   - ioBackend: The I/O backend that the executor's threads use.
///   - benchmark: The benchmark to measure.
@available(anyAppleOS 27.0, *)
func runTCPRequestResponse(
  connections: Int,
  idleConnections: Int = 0,
  requestsPerConnection: Int,
  poolSize: Int = 1,
  ioBackend: PThreadIOBackend,
  benchmark: Benchmark
) async throws {
  var buffers = UniqueArray<ConnectionBuffers>(minimumCapacity: connections)
  for _ in 0..<connections {
    buffers.append(ConnectionBuffers())
  }

  try await PThreadTaskExecutor.withExecutor(name: "TCPRequestResponse", poolSize: poolSize, ioBackend: ioBackend) {
    executor in
    try await withTaskExecutorPreference(executor) {
      let listener = try await TCPListener.bind(to: .v4(SocketAddress.V4(address: .loopback, port: 0)))
      let address = try listener.localAddress

      try await withThrowingTaskGroup { idleGroup in
        var idleClients = UniqueArray<TCPConnection>(minimumCapacity: idleConnections)
        for _ in 0..<idleConnections {
          idleClients.append(try await TCPConnection.connect(to: address))
          let server = try await listener.accept()
          var serverBox: TCPConnection? = consume server
          idleGroup.addTask {
            var server = serverBox.take()!
            try await runIdleServer(on: &server)
            try await server.close()
          }
        }

        benchmark.startMeasurement()
        try await runActiveConnections(
          connections: connections,
          requestsPerConnection: requestsPerConnection,
          listener: listener,
          address: address,
          buffers: &buffers
        )
        benchmark.stopMeasurement()

        // Closing the idle clients ends the reads of their servers.
        while let client = idleClients.popLast() {
          try await client.close()
        }
        try await idleGroup.waitForAll()
      }

      try await listener.close()
    }
  }
}

@available(anyAppleOS 27.0, *)
private struct ConnectionBuffers: ~Copyable {
  /// The array that the client sends its requests from and reads the responses into, which starts out with
  /// the first request.
  var client = UniqueArray<UInt8>(repeating: 0, count: messageSize)

  /// The array that the server reads the requests into and sends the responses from.
  var server = UniqueArray<UInt8>(minimumCapacity: messageSize)
}

@available(anyAppleOS 27.0, *)
private struct Peer: ~Copyable {
  /// The peer's connection.
  var connection: TCPConnection

  /// The array that the peer reads into and writes from.
  var buffer: UniqueArray<UInt8>
}

/// Sets up the active connections one after another.
@available(anyAppleOS 27.0, *)
private func runActiveConnections(
  connections: Int,
  requestsPerConnection: Int,
  listener: borrowing TCPListener,
  address: SocketAddress,
  buffers: inout UniqueArray<ConnectionBuffers>
) async throws {
  try await withThrowingTaskGroup { group in
    for _ in 0..<connections {
      let connectionBuffers = buffers.removeLast()
      let client = Peer(connection: try await TCPConnection.connect(to: address), buffer: connectionBuffers.client)
      let server = Peer(connection: try await listener.accept(), buffer: connectionBuffers.server)

      // A noncopyable value cannot be consumed out of a closure capture, so the
      // connections and their arrays are moved into the child tasks through optionals.
      var clientBox: Peer? = consume client
      var serverBox: Peer? = consume server
      group.addTask {
        var client = clientBox.take()!
        try await runClient(&client, numberOfRequests: requestsPerConnection)
        try await client.connection.close()
      }
      group.addTask {
        var server = serverBox.take()!
        try await runServer(&server)
        try await server.connection.close()
      }
    }
    try await group.waitForAll()
  }
}

@available(anyAppleOS 27.0, *)
private func runClient(_ client: inout Peer, numberOfRequests: Int) async throws {
  for _ in 0..<numberOfRequests {
    try await client.connection.write(from: client.buffer.span.bytes)
    if try await readMessage(from: &client.connection, into: &client.buffer) == false {
      throw RequestResponseError.unexpectedEndOfStream
    }
  }
}

@available(anyAppleOS 27.0, *)
private func runServer(_ server: inout Peer) async throws {
  while try await readMessage(from: &server.connection, into: &server.buffer) {
    try await server.connection.write(from: server.buffer.span.bytes)
  }
}

@available(anyAppleOS 27.0, *)
private func readMessage(
  from connection: inout TCPConnection,
  into buffer: inout UniqueArray<UInt8>
) async throws -> Bool {
  buffer.removeAll()
  while buffer.count < messageSize {
    let missingByteCount = messageSize - buffer.count
    let count = try await buffer.append(addingByteCount: missingByteCount) { output in
      try await connection.read(into: &output)
    }
    if count == 0 {
      guard buffer.isEmpty else {
        throw RequestResponseError.unexpectedEndOfStream
      }
      return false
    }
  }
  return true
}

/// Waits in a read until the client closes the connection.
@available(anyAppleOS 27.0, *)
private func runIdleServer(on connection: inout TCPConnection) async throws {
  var buffer = UniqueArray<UInt8>(minimumCapacity: 1)
  let count = try await buffer.append(addingByteCount: 1) { output in
    try await connection.read(into: &output)
  }
  if count != 0 {
    throw RequestResponseError.unexpectedRequestOnIdleConnection
  }
}

private enum RequestResponseError: Error {
  /// The peer closed the connection in the middle of a message.
  case unexpectedEndOfStream

  /// An idle connection received a request.
  case unexpectedRequestOnIdleConnection
}
