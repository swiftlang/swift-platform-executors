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
/// A scheduler that can perform UDP socket operations.
@available(anyAppleOS 27.0, *)
public protocol UDPSocketOperationScheduler<UDPSocket>: OperationScheduler {
  // TODO: Make the handle `~Copyable` again, see `TCPSocketOperationScheduler`.

  /// The handle identifying a UDP socket of this scheduler.
  associatedtype UDPSocket: Sendable

  /// Creates a new socket and binds it to the given address.
  ///
  /// - Parameter address: The address to bind the socket to.
  /// - Returns: The bound socket.
  func bind(to address: SocketAddress) async throws(IOError) -> UDPSocket

  /// Creates a new socket and connects it to the given address.
  ///
  /// A connected socket sends to and receives from only that peer, which it reads from and writes to with
  /// ``read(socket:into:)`` and ``write(socket:from:)``.
  ///
  /// - Parameter address: The address of the peer.
  /// - Returns: The connected socket.
  func connectUDP(to address: SocketAddress) async throws(IOError) -> UDPSocket

  /// Connects a bound socket to the given address.
  ///
  /// - Parameters:
  ///   - socket: The socket to connect.
  ///   - address: The address of the peer.
  func connectUDP(socket: borrowing UDPSocket, to address: SocketAddress) async throws(IOError)

  /// Receives one datagram into the free capacity of the given buffer.
  ///
  /// The bytes are appended to the buffer. A datagram that is larger than the free capacity of the buffer is
  /// truncated, and its remaining bytes are discarded.
  ///
  /// - Parameters:
  ///   - socket: The socket to receive from.
  ///   - buffer: The buffer to receive into.
  /// - Returns: The number of bytes received and the address of the sender.
  func receive(
    socket: borrowing UDPSocket,
    into buffer: inout OutputRawSpan
  ) async throws(IOError) -> (count: Int, sender: SocketAddress)

  /// Sends the given buffer as one datagram to the given address.
  ///
  /// - Parameters:
  ///   - socket: The socket to send from.
  ///   - buffer: The bytes of the datagram.
  ///   - address: The address to send the datagram to.
  /// - Returns: The number of bytes sent.
  func send(
    socket: borrowing UDPSocket,
    from buffer: RawSpan,
    to address: SocketAddress
  ) async throws(IOError) -> Int

  /// Receives one datagram from the peer of a connected socket into the free capacity of the given buffer.
  ///
  /// The bytes are appended to the buffer. A datagram that is larger than the free capacity of the buffer is
  /// truncated, and its remaining bytes are discarded.
  ///
  /// - Parameters:
  ///   - socket: The connected socket to read from.
  ///   - buffer: The buffer to read into.
  /// - Returns: The number of bytes received.
  func read(socket: borrowing UDPSocket, into buffer: inout OutputRawSpan) async throws(IOError) -> Int

  /// Sends the given buffer as one datagram to the peer of a connected socket.
  ///
  /// - Parameters:
  ///   - socket: The connected socket to write to.
  ///   - buffer: The bytes of the datagram.
  /// - Returns: The number of bytes sent.
  func write(socket: borrowing UDPSocket, from buffer: RawSpan) async throws(IOError) -> Int

  /// Closes a socket.
  ///
  /// - Parameter socket: The socket to close.
  func close(socket: consuming UDPSocket) async throws(IOError)

  /// Returns the address that a socket is bound to.
  ///
  /// This is how a socket that was bound to port zero reports the port the platform picked for it.
  ///
  /// - Parameter socket: The socket to return the address of.
  /// - Returns: The address that the socket is bound to.
  func localAddress(of socket: borrowing UDPSocket) throws(IOError) -> SocketAddress

  /// Returns the address of the peer that a connected socket is connected to.
  ///
  /// - Parameter socket: The connected socket to return the peer of.
  /// - Returns: The address of the peer.
  func remoteAddress(of socket: borrowing UDPSocket) throws(IOError) -> SocketAddress
}
#endif
