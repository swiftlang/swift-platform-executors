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

// MARK: - UDP socket operations

/// A pool performs every operation on the executor that the calling thread runs, or on the next one if it does not
/// run one.
@available(anyAppleOS 27.0, *)
extension PThreadTaskExecutor: UDPSocketOperationScheduler {
  public typealias UDPSocket = PThreadUDPSocket

  public func bind(to address: SocketAddress) async throws(IOError) -> UDPSocket {
    try await self.current().bind(to: address)
  }

  public func receive(
    socket: borrowing UDPSocket,
    into buffer: inout OutputRawSpan
  ) async throws(IOError) -> (count: Int, sender: SocketAddress) {
    try await self.current().receive(socket: socket, into: &buffer)
  }

  public func send(
    socket: borrowing UDPSocket,
    from buffer: RawSpan,
    to address: SocketAddress
  ) async throws(IOError) -> Int {
    try await self.current().send(socket: socket, from: buffer, to: address)
  }

  public func close(socket: consuming UDPSocket) async throws(IOError) {
    try await self.current().close(socket: socket)
  }

  public func localAddress(of socket: borrowing UDPSocket) throws(IOError) -> SocketAddress {
    try unsafe self.executors[0].localAddress(of: socket)
  }
}
#endif
#endif
