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
#if os(Linux) || os(Android) || os(FreeBSD) || canImport(Darwin)
@_spi(ExperimentalScheduling) @_spi(ConcurrencyExecutors) @_spi(ExperimentalCustomExecutors) import _Concurrency

// MARK: - TCP socket operations

/// A pool forwards every operation to the executor that services the socket. A socket stays on the executor
/// that created it.
@available(anyAppleOS 27.0, *)
extension PThreadTaskExecutor: TCPSocketOperationScheduler {
  public typealias TCPConnection = PThreadTCPConnection
  public typealias TCPListener = PThreadTCPListener

  public func connect(to address: SocketAddress) async throws(IOError) -> TCPConnection {
    try await self.next().connect(to: address)
  }

  public func listen(on address: SocketAddress, backlog: Int) async throws(IOError) -> TCPListener {
    try await self.next().listen(on: address, backlog: backlog)
  }

  public func accept(listener: borrowing TCPListener) async throws(IOError) -> TCPConnection {
    try await self.executors[listener.executorIndex].accept(listener: listener)
  }

  public func read(
    connection: borrowing TCPConnection,
    into buffer: inout OutputRawSpan
  ) async throws(IOError) -> Int {
    try await self.executors[connection.executorIndex].read(connection: connection, into: &buffer)
  }

  public func write(connection: borrowing TCPConnection, from buffer: RawSpan) async throws(IOError) -> Int {
    try await self.executors[connection.executorIndex].write(connection: connection, from: buffer)
  }

  public func shutdown(
    connection: borrowing TCPConnection,
    direction: SocketShutdownDirection
  ) async throws(IOError) {
    try await self.executors[connection.executorIndex].shutdown(connection: connection, direction: direction)
  }

  public func close(connection: consuming TCPConnection) async throws(IOError) {
    try await self.executors[connection.executorIndex].close(connection: connection)
  }

  public func close(listener: consuming TCPListener) async throws(IOError) {
    try await self.executors[listener.executorIndex].close(listener: listener)
  }

  public func localAddress(of connection: borrowing TCPConnection) throws(IOError) -> SocketAddress {
    try self.executors[connection.executorIndex].localAddress(of: connection)
  }

  public func localAddress(of listener: borrowing TCPListener) throws(IOError) -> SocketAddress {
    try self.executors[listener.executorIndex].localAddress(of: listener)
  }
}

#endif
#endif
