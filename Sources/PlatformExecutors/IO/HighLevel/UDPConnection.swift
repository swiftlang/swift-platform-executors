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
/// A UDP socket that exchanges datagrams with one peer.
///
/// A connection is created by connecting to a peer with ``connect(to:)``, or by connecting a bound
/// ``UDPSocket`` with ``UDPSocket/connect(to:)``. The platform drops the datagrams that other peers send to
/// it.
///
/// A connection uniquely owns the underlying platform resource, so it cannot be copied. It must be closed
/// explicitly with ``close()`` since closing is an asynchronous operation, and destroying a connection
/// without closing it traps.
///
/// ```swift
/// var connection = try await UDPConnection.connect(to: address)
/// try await connection.write(from: request)
/// let count = try await connection.read(into: &response)
/// try await connection.close()
/// ```
@available(anyAppleOS 27.0, *)
public struct UDPConnection: ~Copyable, Sendable {
  private var core: UDPCore

  init(core: consuming UDPCore) {
    self.core = core
  }

  /// Creates a new socket and connects it to the given address.
  ///
  /// The platform picks the local address of the socket, which ``localAddress`` reports afterwards. Connecting
  /// does not send anything, so it succeeds even if nobody listens at the address.
  ///
  /// - Parameter address: The address of the peer.
  /// - Returns: The connected socket.
  public static func connect(to address: SocketAddress) async throws(IOError) -> UDPConnection {
    UDPConnection(core: try await UDPCore.connect(to: address))
  }

  /// The address that the socket is bound to locally.
  public var localAddress: SocketAddress {
    get throws(IOError) {
      try self.core.localAddress
    }
  }

  /// The address of the peer.
  public var remoteAddress: SocketAddress {
    get throws(IOError) {
      try self.core.remoteAddress
    }
  }

  /// Reads one datagram from the peer into the free capacity of the given buffer.
  ///
  /// The bytes are appended to the buffer. A datagram that is larger than the free capacity of the buffer is
  /// truncated, and its remaining bytes are discarded.
  ///
  /// - Parameter buffer: The buffer to read into.
  /// - Returns: The number of bytes received.
  @discardableResult
  public mutating func read(into buffer: inout OutputRawSpan) async throws(IOError) -> Int {
    try await UDPCore.read(into: &buffer, socket: self.core.socket, on: self.core.scheduler)
  }

  /// Sends the bytes of the given buffer as one datagram to the peer.
  ///
  /// - Parameter buffer: The bytes of the datagram.
  public mutating func write(from buffer: RawSpan) async throws(IOError) {
    try await UDPCore.write(from: buffer, socket: self.core.socket, on: self.core.scheduler)
  }

  /// Reads one datagram from the peer into a buffer that the platform provides.
  ///
  /// A datagram that is larger than the buffer is truncated, and its remaining bytes are discarded.
  ///
  /// - Returns: The buffer with the bytes of the datagram, which the caller has to return.
  public mutating func read() async throws(IOError) -> LeasedBuffer {
    try await UDPCore.read(socket: self.core.socket, on: self.core.scheduler)
  }

  /// Reads one datagram from the peer into a buffer that the platform provides, and hands it to the given
  /// closure.
  ///
  /// A datagram that is larger than the buffer is truncated, and its remaining bytes are discarded.
  ///
  /// - Parameter body: The closure to invoke with the bytes of the datagram.
  /// - Returns: Whatever is returned by `body`.
  public mutating func read<Return: ~Copyable>(
    _ body: (inout OutputRawSpan) -> Return
  ) async throws(IOError) -> Return {
    try await UDPCore.read(socket: self.core.socket, on: self.core.scheduler, body)
  }

  /// Sends the datagram that the given closure produces to the peer, using a buffer that the platform provides.
  ///
  /// - Parameter body: The closure to invoke with the buffer to fill.
  /// - Returns: Whatever is returned by `body`.
  public mutating func write<Return: ~Copyable>(
    _ body: (inout OutputRawSpan) -> Return
  ) async throws(IOError) -> Return {
    try await UDPCore.write(socket: self.core.socket, on: self.core.scheduler, body)
  }

  /// Closes the connection.
  public consuming func close() async throws(IOError) {
    try await self.core.close()
  }
}

// MARK: - Reading and writing concurrently

@available(anyAppleOS 27.0, *)
extension UDPConnection {
  /// The read direction of a connection, lent out by ``UDPConnection/withSplit(_:)``.
  public struct ReadHalf: ~Copyable, ~Escapable, Sendable {
    /// The scheduler that services the socket.
    private let scheduler: any UDPSocketOperationScheduler

    /// The scheduler's handle of the socket.
    private let socket: (any Sendable)?

    @_lifetime(borrow owner)
    fileprivate init(_ owner: borrowing UDPConnection) {
      self.scheduler = owner.core.scheduler
      self.socket = owner.core.socket
    }

    /// Reads one datagram from the peer into the free capacity of the given buffer.
    ///
    /// - Parameter buffer: The buffer to read into.
    /// - Returns: The number of bytes received.
    @discardableResult
    public mutating func read(into buffer: inout OutputRawSpan) async throws(IOError) -> Int {
      try await UDPCore.read(into: &buffer, socket: self.socket, on: self.scheduler)
    }

    /// Reads one datagram from the peer into a buffer that the platform provides, and hands it to the given
    /// closure.
    ///
    /// - Parameter body: The closure to invoke with the bytes of the datagram.
    /// - Returns: Whatever is returned by `body`.
    public mutating func read<Return: ~Copyable>(
      _ body: (inout OutputRawSpan) -> Return
    ) async throws(IOError) -> Return {
      try await UDPCore.read(socket: self.socket, on: self.scheduler, body)
    }
  }

  /// The write direction of a connection, lent out by ``UDPConnection/withSplit(_:)``.
  public struct WriteHalf: ~Copyable, ~Escapable, Sendable {
    /// The scheduler that services the socket.
    private let scheduler: any UDPSocketOperationScheduler

    /// The scheduler's handle of the socket.
    private let socket: (any Sendable)?

    @_lifetime(borrow owner)
    fileprivate init(_ owner: borrowing UDPConnection) {
      self.scheduler = owner.core.scheduler
      self.socket = owner.core.socket
    }

    /// Sends the bytes of the given buffer as one datagram to the peer.
    ///
    /// - Parameter buffer: The bytes of the datagram.
    public mutating func write(from buffer: RawSpan) async throws(IOError) {
      try await UDPCore.write(from: buffer, socket: self.socket, on: self.scheduler)
    }

    /// Sends the datagram that the given closure produces to the peer, using a buffer that the platform
    /// provides.
    ///
    /// - Parameter body: The closure to invoke with the buffer to fill.
    /// - Returns: Whatever is returned by `body`.
    public mutating func write<Return: ~Copyable>(
      _ body: (inout OutputRawSpan) -> Return
    ) async throws(IOError) -> Return {
      try await UDPCore.write(socket: self.socket, on: self.scheduler, body)
    }
  }

  /// Lends the read and the write direction of the connection to the given closure.
  ///
  /// The halves can be used concurrently allowing protocols to send and receive independently. Their
  /// methods are `mutating`, so that every half is only used by one task at a time.
  ///
  /// - Important: The halves cannot escape the closure, so the connection keeps owning the platform
  ///   resource and must still be closed afterwards.
  ///
  /// - Parameter body: The closure that the halves are lent to.
  /// - Returns: The value that the closure returned.
  public nonisolated(nonsending) func withSplit<Return, Failure: Error>(
    _ body: nonisolated(nonsending) (inout ReadHalf, inout WriteHalf) async throws(Failure) -> Return
  ) async throws(Failure) -> Return {
    var readHalf = ReadHalf(self)
    var writeHalf = WriteHalf(self)
    return try await body(&readHalf, &writeHalf)
  }
}
#endif
