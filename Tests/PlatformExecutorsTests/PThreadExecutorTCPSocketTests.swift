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

#if ExperimentalIO
#if os(Linux) || os(FreeBSD) || canImport(Darwin)

import Testing
@_spi(ExperimentalScheduling) @_spi(ConcurrencyExecutors) @_spi(ExperimentalCustomExecutors) import _Concurrency
@_spi(ExperimentalScheduling) @_spi(ConcurrencyExecutors) @_spi(ExperimentalCustomExecutors) import PlatformExecutors

@Suite
struct PThreadExecutorTCPSocketTests {
  @Test
  @available(anyAppleOS 27.0, *)
  func listenBindsToAPortAndCloses() async throws {
    try await PThreadExecutor.withExecutor(name: "TCPSocketTest") { executor in
      let listener = try await executor.listen(
        on: .v4(SocketAddress.V4(address: .loopback, port: 0)),
        backlog: 1
      )
      let address = try executor.localAddress(of: listener)
      try await executor.close(listener: listener)

      guard case .v4(let v4) = address else {
        Issue.record("Expected an IPv4 address but got \(address)")
        return
      }
      #expect(v4.address == .loopback)
      #expect(v4.port != 0)
    }
  }

  @Test
  @available(anyAppleOS 27.0, *)
  func connectToRefusedPortFails() async throws {
    try await PThreadExecutor.withExecutor(name: "TCPSocketTest") { executor in
      try await withRefusingAddress { address in
        await #expect(throws: IOError.self) {
          _ = try await executor.connect(to: address)
        }
      }
    }
  }

  @Test
  @available(anyAppleOS 27.0, *)
  func connectToListenerSucceeds() async throws {
    try await PThreadExecutor.withExecutor(name: "TCPSocketTest") { executor in
      let listener = try await executor.listen(
        on: .v4(SocketAddress.V4(address: .loopback, port: 0)),
        backlog: 1
      )
      let listenerAddress = try executor.localAddress(of: listener)

      let connection = try await executor.connect(to: listenerAddress)
      let connectionAddress = try executor.localAddress(of: connection)
      try await executor.close(connection: connection)
      try await executor.close(listener: listener)

      guard case .v4(let listenerV4) = listenerAddress, case .v4(let connectionV4) = connectionAddress else {
        Issue.record("Expected IPv4 addresses but got \(listenerAddress) and \(connectionAddress)")
        return
      }

      #expect(connectionV4.address == .loopback)
      #expect(connectionV4.port != 0)
      #expect(connectionV4.port != listenerV4.port)
    }
  }

  @Test
  @available(anyAppleOS 27.0, *)
  func echo() async throws {
    try await PThreadExecutor.withExecutor(name: "TCPSocketTest") { executor in
      try await Self.echo(on: executor)
    }
  }

  @Test
  @available(anyAppleOS 27.0, *)
  func echoOnTheExecutor() async throws {
    try await PThreadExecutor.withExecutor(name: "TCPSocketTest") { executor in
      try await withTaskExecutorPreference(executor) {
        try await Self.echo(on: executor)
      }
    }
  }

  /// Echoes a payload through a connection between a client and a server task.
  @available(anyAppleOS 27.0, *)
  private static func echo(on executor: PThreadExecutor) async throws {
    let listener = try await executor.listen(
      on: .v4(SocketAddress.V4(address: .loopback, port: 0)),
      backlog: 1
    )
    let address = try executor.localAddress(of: listener)
    let payload = Array("Hello from the PThreadExecutor".utf8)

    try await withThrowingTaskGroup(of: [UInt8].self) { group in
      group.addTask {
        let client = try await executor.connect(to: address)
        try await executor.write(all: payload, to: client)
        try await executor.shutdown(connection: client, direction: .write)
        let echoed = try await executor.readUntilEndOfStream(from: client)
        try await executor.close(connection: client)
        return echoed
      }

      let server = try await executor.accept(listener: listener)
      let received = try await executor.readUntilEndOfStream(from: server)
      try await executor.write(all: received, to: server)
      try await executor.close(connection: server)

      #expect(received == payload)
      let echoed = try await group.next()
      #expect(echoed == payload)
    }

    try await executor.close(listener: listener)
  }

  // TODO: Enable this again once the handles of `TCPSocketOperationScheduler` are `~Copyable`.
  @Test(.disabled("The handles are copyable and have no deinit for now."))
  @available(anyAppleOS 27.0, *)
  func droppingAListenerWithoutClosingItTraps() async throws {
    await #expect(processExitsWith: .failure) {
      try await PThreadExecutor.withExecutor(name: "TCPSocketTest") { executor in
        let listener = try await executor.listen(
          on: .v4(SocketAddress.V4(address: .loopback, port: 0)),
          backlog: 1
        )
        // Dropping the listener instead of closing it has to trap
        // since it would otherwise leak the descriptor.
        _ = consume listener
      }
    }
  }
}

@available(anyAppleOS 27.0, *)
extension PThreadExecutor {
  /// Reads once, returning at most `count` bytes, or none at the end of the stream.
  fileprivate func read(
    from connection: TCPConnection,
    count: Int
  ) async throws(IOError) -> [UInt8] {
    let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: count, alignment: 1)
    defer {
      buffer.deallocate()
    }

    var output = OutputRawSpan(buffer: buffer, initializedCount: 0)
    let received = try await self.read(connection: connection, into: &output)
    let initializedCount = output.finalize(for: buffer)
    #expect(initializedCount == received)
    return Array(UnsafeRawBufferPointer(rebasing: buffer[..<received]))
  }

  /// Reads until the peer closed its side of the connection.
  fileprivate func readUntilEndOfStream(from connection: TCPConnection) async throws(IOError) -> [UInt8] {
    var received = [UInt8]()
    while true {
      let chunk = try await self.read(from: connection, count: 1024)
      if chunk.isEmpty {
        return received
      }
      received += chunk
    }
  }

  /// Writes all of the given bytes, which can take several writes.
  fileprivate func write(all bytes: [UInt8], to connection: TCPConnection) async throws(IOError) {
    var remaining = bytes[...]
    while !remaining.isEmpty {
      let written = try await self.write(connection: connection, from: remaining.span.bytes)
      remaining = remaining.dropFirst(written)
    }
  }
}

#endif
#endif
