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
/// A UDP socket that sends datagrams to, and receives datagrams from, any peer.
///
/// A socket is created by binding it to a local address with ``bind(to:)``. To exchange datagrams with one
/// peer only, connect it with ``connect(to:)``, which turns it into a ``UDPConnection``.
///
/// A socket uniquely owns the underlying platform resource, so it cannot be copied. It must be closed
/// explicitly with ``close()`` since closing is an asynchronous operation, and destroying a socket without
/// closing it traps.
///
/// ```swift
/// var socket = try await UDPSocket.bind(to: address)
/// let (count, sender) = try await socket.receive(into: &datagram)
/// try await socket.send(from: reply, to: sender)
/// try await socket.close()
/// ```
@available(anyAppleOS 27.0, *)
public struct UDPSocket: ~Copyable, Sendable {
  private var core: UDPCore

  private init(core: consuming UDPCore) {
    self.core = core
  }

  /// Creates a new socket and binds it to the given address.
  ///
  /// - Parameter address: The address to bind to. Binding to port zero lets the platform pick a free port,
  ///   which ``localAddress`` reports afterwards.
  /// - Returns: The bound socket.
  public static func bind(to address: SocketAddress) async throws(IOError) -> UDPSocket {
    UDPSocket(core: try await UDPCore.bind(to: address))
  }

  /// The address that the socket is bound to locally.
  public var localAddress: SocketAddress {
    get throws(IOError) {
      try self.core.localAddress
    }
  }

  /// Receives one datagram into the free capacity of the given buffer.
  ///
  /// The bytes are appended to the buffer. A datagram that is larger than the free capacity of the buffer is
  /// truncated, and its remaining bytes are discarded.
  ///
  /// - Parameter buffer: The buffer to receive into.
  /// - Returns: The number of bytes received and the address of the sender.
  @discardableResult
  public mutating func receive(
    into buffer: inout OutputRawSpan
  ) async throws(IOError) -> (count: Int, sender: SocketAddress) {
    try await UDPCore.receive(into: &buffer, socket: self.core.socket, on: self.core.scheduler)
  }

  /// Sends the bytes of the given buffer as one datagram to the given address.
  ///
  /// - Parameters:
  ///   - buffer: The bytes of the datagram.
  ///   - address: The address to send the datagram to.
  public mutating func send(
    from buffer: RawSpan,
    to address: SocketAddress
  ) async throws(IOError) {
    try await UDPCore.send(from: buffer, to: address, socket: self.core.socket, on: self.core.scheduler)
  }

  /// Receives one datagram into a buffer that the platform provides.
  ///
  /// A datagram that is larger than the buffer is truncated, and its remaining bytes are discarded.
  ///
  /// - Returns: The datagram, whose buffer the caller has to return.
  public mutating func receive() async throws(IOError) -> ReceivedDatagram {
    try await UDPCore.receive(socket: self.core.socket, on: self.core.scheduler)
  }

  /// Receives one datagram into a buffer that the platform provides, and hands it to the given closure.
  ///
  /// A datagram that is larger than the buffer is truncated, and its remaining bytes are discarded.
  ///
  /// - Parameter body: The closure to invoke with the bytes of the datagram and the address of the sender.
  /// - Returns: Whatever is returned by `body`.
  public mutating func receive<Return: ~Copyable>(
    _ body: (inout OutputRawSpan, SocketAddress) -> Return
  ) async throws(IOError) -> Return {
    try await UDPCore.receive(socket: self.core.socket, on: self.core.scheduler, body)
  }

  /// Sends the datagram that the given closure produces to the given address, using a buffer that the platform
  /// provides.
  ///
  /// - Parameters:
  ///   - address: The address to send the datagram to.
  ///   - body: The closure to invoke with the buffer to fill.
  /// - Returns: Whatever is returned by `body`.
  @discardableResult
  public mutating func send<Return: ~Copyable>(
    to address: SocketAddress,
    _ body: (inout OutputRawSpan) -> Return
  ) async throws(IOError) -> Return {
    try await UDPCore.send(to: address, socket: self.core.socket, on: self.core.scheduler, body)
  }

  /// Connects the socket to the given address, so that it only exchanges datagrams with that peer.
  ///
  /// The socket keeps its local address. Connecting does not send anything, so it succeeds even if nobody
  /// listens at the address. The platform drops the datagrams of everyone else from then on.
  ///
  /// - Important: If connecting fails the socket is closed.
  ///
  /// - Parameter address: The address of the peer.
  /// - Returns: The connected socket.
  public consuming func connect(to address: SocketAddress) async throws(IOError) -> UDPConnection {
    UDPConnection(core: try await self.core.connected(to: address))
  }

  /// Closes the socket.
  public consuming func close() async throws(IOError) {
    try await self.core.close()
  }
}

// MARK: - Receiving and sending concurrently

@available(anyAppleOS 27.0, *)
extension UDPSocket {
  /// The receiving direction of a socket, lent out by ``UDPSocket/withSplit(_:)``.
  public struct ReceiveHalf: ~Copyable, ~Escapable, Sendable {
    /// The scheduler that services the socket.
    private let scheduler: any UDPSocketOperationScheduler

    /// The scheduler's handle of the socket.
    private let socket: (any Sendable)?

    @_lifetime(borrow owner)
    fileprivate init(_ owner: borrowing UDPSocket) {
      self.scheduler = owner.core.scheduler
      self.socket = owner.core.socket
    }

    /// Receives one datagram into the free capacity of the given buffer.
    ///
    /// The bytes are appended to the buffer. A datagram that is larger than the free capacity of the buffer
    /// is truncated, and its remaining bytes are discarded.
    ///
    /// - Parameter buffer: The buffer to receive into.
    /// - Returns: The number of bytes received and the address of the sender.
    @discardableResult
    public mutating func receive(
      into buffer: inout OutputRawSpan
    ) async throws(IOError) -> (count: Int, sender: SocketAddress) {
      try await UDPCore.receive(into: &buffer, socket: self.socket, on: self.scheduler)
    }

    /// Receives one datagram into a buffer that the platform provides, and hands it to the given closure.
    ///
    /// - Parameter body: The closure to invoke with the bytes of the datagram and the address of the sender.
    /// - Returns: Whatever is returned by `body`.
    public mutating func receive<Return: ~Copyable>(
      _ body: (inout OutputRawSpan, SocketAddress) -> Return
    ) async throws(IOError) -> Return {
      try await UDPCore.receive(socket: self.socket, on: self.scheduler, body)
    }
  }

  /// The sending direction of a socket, lent out by ``UDPSocket/withSplit(_:)``.
  public struct SendHalf: ~Copyable, ~Escapable, Sendable {
    /// The scheduler that services the socket.
    private let scheduler: any UDPSocketOperationScheduler

    /// The scheduler's handle of the socket.
    private let socket: (any Sendable)?

    @_lifetime(borrow owner)
    fileprivate init(_ owner: borrowing UDPSocket) {
      self.scheduler = owner.core.scheduler
      self.socket = owner.core.socket
    }

    /// Sends the bytes of the given buffer as one datagram to the given address.
    ///
    /// - Parameters:
    ///   - buffer: The bytes of the datagram.
    ///   - address: The address to send the datagram to.
    public mutating func send(from buffer: RawSpan, to address: SocketAddress) async throws(IOError) {
      try await UDPCore.send(from: buffer, to: address, socket: self.socket, on: self.scheduler)
    }

    /// Sends the datagram that the given closure produces to the given address, using a buffer that the
    /// platform provides.
    ///
    /// - Parameters:
    ///   - address: The address to send the datagram to.
    ///   - body: The closure to invoke with the buffer to fill.
    /// - Returns: Whatever is returned by `body`.
    @discardableResult
    public mutating func send<Return: ~Copyable>(
      to address: SocketAddress,
      _ body: (inout OutputRawSpan) -> Return
    ) async throws(IOError) -> Return {
      try await UDPCore.send(to: address, socket: self.socket, on: self.scheduler, body)
    }
  }

  /// Lends the receiving and the sending direction of the socket to the given closure.
  ///
  /// The halves can be used concurrently allowing protocols to send and receive independently. Their
  /// methods are `mutating`, so that every half is only used by one task at a time.
  ///
  /// ```swift
  /// try await socket.withSplit { receiveHalf, sendHalf in
  ///   try await withConcurrently {
  ///     try await receiveReplies(from: &receiveHalf)
  ///   } _: {
  ///     try await sendHalf.send(from: request, to: address)
  ///   }
  /// }
  /// ```
  ///
  /// - Important: The halves cannot escape the closure, so the socket keeps owning the platform resource
  ///   and must still be closed afterwards.
  ///
  /// - Parameter body: The closure that the halves are lent to.
  /// - Returns: The value that the closure returned.
  public nonisolated(nonsending) func withSplit<Return, Failure: Error>(
    _ body: nonisolated(nonsending) (inout ReceiveHalf, inout SendHalf) async throws(Failure) -> Return
  ) async throws(Failure) -> Return {
    var receiveHalf = ReceiveHalf(self)
    var sendHalf = SendHalf(self)
    return try await body(&receiveHalf, &sendHalf)
  }
}
#endif
