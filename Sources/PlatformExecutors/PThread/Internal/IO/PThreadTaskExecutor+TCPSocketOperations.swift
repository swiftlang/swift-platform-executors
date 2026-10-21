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

/// A pool performs every operation on the executor that the calling thread runs, or on the next one if it does not
/// run one.
@available(anyAppleOS 27.0, *)
extension PThreadTaskExecutor: TCPSocketOperationScheduler {
  public typealias TCPConnection = PThreadTCPConnection
  public typealias TCPListener = PThreadTCPListener

  public func connect(to address: SocketAddress) async throws(IOError) -> TCPConnection {
    try await self.current().connect(to: address)
  }

  public func listen(on address: SocketAddress, backlog: Int) async throws(IOError) -> TCPListener {
    try await self.current().listen(on: address, backlog: backlog)
  }

  public func accept(listener: borrowing TCPListener) async throws(IOError) -> TCPConnection {
    try await self.current().accept(listener: listener)
  }

  public func read(
    connection: borrowing TCPConnection,
    into buffer: inout OutputRawSpan
  ) async throws(IOError) -> Int {
    try await self.current().read(connection: connection, into: &buffer)
  }

  public func write(connection: borrowing TCPConnection, from buffer: RawSpan) async throws(IOError) -> Int {
    try await self.current().write(connection: connection, from: buffer)
  }

  public func shutdown(
    connection: borrowing TCPConnection,
    direction: SocketShutdownDirection
  ) async throws(IOError) {
    try await self.current().shutdown(connection: connection, direction: direction)
  }

  public func close(connection: consuming TCPConnection) async throws(IOError) {
    try await self.current().close(connection: connection)
  }

  public func close(listener: consuming TCPListener) async throws(IOError) {
    try await self.current().close(listener: listener)
  }

  public func localAddress(of connection: borrowing TCPConnection) throws(IOError) -> SocketAddress {
    // Reading the address is a plain syscall that no executor has to perform.
    try unsafe self.executors[0].localAddress(of: connection)
  }

  public func localAddress(of listener: borrowing TCPListener) throws(IOError) -> SocketAddress {
    try unsafe self.executors[0].localAddress(of: listener)
  }
}

#endif
#endif
