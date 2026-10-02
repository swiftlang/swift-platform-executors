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
      // Bind a listener to get a port that is not listening once it is closed again.
      let listener = try await executor.listen(
        on: .v4(SocketAddress.V4(address: .loopback, port: 0)),
        backlog: 1
      )
      let address = try executor.localAddress(of: listener)
      try await executor.close(listener: listener)

      await #expect(throws: IOError.self) {
        _ = try await executor.connect(to: address)
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

// MARK: - Awaiting the operations

/// Awaits one operation of the executor.
@available(anyAppleOS 27.0, *)
private func withOperation<Success: ~Copyable>(
  of: Success.Type = Success.self,
  _ submit: (consuming Continuation<Success, IOError>, inout OutputSpan<PThreadExecutor.OperationState>) ->
    OperationRegistration
) async throws(IOError) -> Success {
  let buffer = UnsafeMutableBufferPointer<PThreadExecutor.OperationState>.allocate(capacity: 1)
  defer {
    buffer.deallocate()
  }

  return try await withContinuation(of: Success.self, throwing: IOError.self) { continuation in
    var state = OutputSpan(buffer: buffer, initializedCount: 0)
    _ = submit(continuation, &state)
    // The state must not be destroyed here since the operation might still be in flight.
    _ = state.finalize(for: buffer)
  }
}

@available(anyAppleOS 27.0, *)
extension PThreadExecutor {
  fileprivate func listen(
    on address: SocketAddress,
    backlog: Int
  ) async throws(IOError) -> TCPListener {
    try await withOperation { continuation, state in
      self.submitListen(continuation, state: &state, on: address, backlog: backlog)
    }
  }

  fileprivate func connect(to address: SocketAddress) async throws(IOError) -> TCPConnection {
    try await withOperation { continuation, state in
      self.submitConnect(continuation, state: &state, to: address)
    }
  }

  fileprivate func close(connection: consuming TCPConnection) async throws(IOError) {
    // TODO: Adopt call-once closures once we have them
    var pending: TCPConnection? = consume connection
    try await withOperation(of: Void.self) { continuation, state in
      self.submitClose(continuation, state: &state, connection: pending.take()!)
    }
  }

  fileprivate func close(listener: consuming TCPListener) async throws(IOError) {
    // TODO: Adopt call-once closures once we have them
    var pending: TCPListener? = consume listener
    try await withOperation(of: Void.self) { continuation, state in
      self.submitClose(continuation, state: &state, listener: pending.take()!)
    }
  }
}

#endif
#endif
