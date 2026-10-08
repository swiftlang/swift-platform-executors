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
/// A scheduler that can perform TCP socket operations.
@available(anyAppleOS 27.0, *)
public protocol TCPSocketOperationScheduler<TCPListener, TCPConnection>: OperationScheduler {
  // TODO: Bikeshed the name of this protocol. `socket` might not universal
  // vocabulary across the platforms we support.
  //
  // TODO: Check if and how an existing TCP socket can be adopted.
  //
  // TODO: Need to support a more general endpoint type that accepts hostnames.
  //
  // TODO: Make the handles `~Copyable` again so that the type system tracks
  // their ownership. They are copyable for now since the runtime crashes when
  // it builds the metadata of a parameterized existential whose type argument
  // is noncopyable, e.g. `any TCPSocketOperationScheduler<…>` or a cast to it.

  /// The handle identifying a listening TCP socket of this scheduler.
  associatedtype TCPListener: Sendable

  /// The handle identifying a connected TCP socket of this scheduler.
  associatedtype TCPConnection: Sendable

  /// Submits an operation that creates a new socket and connects it to the given address.
  ///
  /// - Parameters:
  ///   - continuation: The continuation resumed with the connected socket.
  ///   - state: The per-operation state of the scheduler.
  ///   - address: The address to connect to.
  /// - Returns: The registration of the operation.
  func submitConnect(
    _ continuation: consuming Continuation<TCPConnection, IOError>,
    state: inout OutputSpan<OperationState>,
    to address: SocketAddress
  ) -> OperationRegistration

  /// Submits an operation that creates a new socket, binds it to the given
  /// address and starts listening for incoming connections.
  ///
  /// - Parameters:
  ///   - continuation: The continuation resumed with the listening socket.
  ///   - state: The per-operation state of the scheduler.
  ///   - address: The address to bind the socket to.
  ///   - backlog: The maximum number of connections the platform queues up
  ///     before refusing new ones.
  /// - Returns: The registration of the operation.
  func submitListen(
    _ continuation: consuming Continuation<TCPListener, IOError>,
    state: inout OutputSpan<OperationState>,
    on address: SocketAddress,
    backlog: Int
  ) -> OperationRegistration

  /// Submits an operation that accepts the next incoming connection of a
  /// listening socket.
  ///
  /// - Parameters:
  ///   - continuation: The continuation resumed with the accepted socket.
  ///   - state: The per-operation state of the scheduler.
  ///   - listener: The listening socket to accept a connection from.
  /// - Returns: The registration of the operation.
  func submitAccept(
    _ continuation: consuming Continuation<TCPConnection, IOError>,
    state: inout OutputSpan<OperationState>,
    listener: borrowing TCPListener
  ) -> OperationRegistration

  /// Submits an operation that reads from a socket into the given buffer.
  ///
  /// - Important: The buffer must stay alive until the operation has completed
  ///   or has been cancelled since the kernel might be writing into it while
  ///   the caller is suspended.
  ///
  /// - Parameters:
  ///   - continuation: The continuation resumed with the number of bytes read.
  ///     Zero indicates that the peer closed its side of the connection.
  ///   - state: The per-operation state of the scheduler.
  ///   - socket: The socket to read from.
  ///   - buffer: The buffer to read into.
  /// - Returns: The registration of the operation.
  func submitRead(
    _ continuation: consuming Continuation<Int, IOError>,
    state: inout OutputSpan<OperationState>,
    connection: borrowing TCPConnection,
    into buffer: inout OutputRawSpan
  ) -> OperationRegistration

  /// Submits an operation that writes the given buffer to a socket.
  ///
  /// - Important: The buffer must stay alive until the operation has completed
  ///   or has been cancelled since the kernel might be reading from it while
  ///   the caller is suspended.
  ///
  /// - Parameters:
  ///   - continuation: The continuation resumed with the number of bytes
  ///     written. This can be less than the number of bytes in the buffer.
  ///   - state: The per-operation state of the scheduler.
  ///   - socket: The socket to write to.
  ///   - buffer: The buffer to write from.
  /// - Returns: The registration of the operation.
  func submitWrite(
    _ continuation: consuming Continuation<Int, IOError>,
    state: inout OutputSpan<OperationState>,
    connection: borrowing TCPConnection,
    from buffer: RawSpan
  ) -> OperationRegistration

  /// Submits an operation that shuts down one or both directions of a socket.
  ///
  /// Shutting down the write direction sends a `FIN` to the peer, which
  /// observes it as the end of the stream once it has received all data that is
  /// still in flight. The socket can still be read from afterwards, which is
  /// how a protocol signals that it is done sending without discarding what the
  /// peer is still sending.
  ///
  /// - Parameters:
  ///   - continuation: The continuation resumed once the socket is shut down.
  ///   - state: The per-operation state of the scheduler.
  ///   - socket: The socket to shut down.
  ///   - direction: The direction to shut down.
  /// - Returns: The registration of the operation.
  func submitShutdown(
    _ continuation: consuming Continuation<Void, IOError>,
    state: inout OutputSpan<OperationState>,
    connection: borrowing TCPConnection,
    direction: SocketShutdownDirection
  ) -> OperationRegistration

  /// Submits an operation that closes a socket.
  ///
  /// - Parameters:
  ///   - continuation: The continuation resumed once the socket is closed.
  ///   - state: The per-operation state of the scheduler.
  ///   - socket: The socket to close.
  /// - Returns: The registration of the operation.
  func submitClose(
    _ continuation: consuming Continuation<Void, IOError>,
    state: inout OutputSpan<OperationState>,
    connection: consuming TCPConnection
  ) -> OperationRegistration

  /// Submits an operation that closes a listening socket.
  ///
  /// - Parameters:
  ///   - continuation: The continuation resumed once the listening socket is closed.
  ///   - state: The per-operation state of the scheduler.
  ///   - listener: The listening socket to close.
  /// - Returns: The registration of the operation.
  func submitClose(
    _ continuation: consuming Continuation<Void, IOError>,
    state: inout OutputSpan<OperationState>,
    listener: consuming TCPListener
  ) -> OperationRegistration

  /// Returns the address that a connected socket is bound to locally.
  ///
  /// - Parameter connection: The socket to return the local address of.
  /// - Returns: The address that the socket is bound to locally.
  func localAddress(of connection: borrowing TCPConnection) throws(IOError) -> SocketAddress

  /// Returns the address that a listening socket is bound to.
  ///
  /// This is how a listening socket that was bound to port zero reports the port the platform picked for it.
  ///
  /// - Parameter listener: The listening socket to return the address of.
  /// - Returns: The address that the listening socket is bound to.
  func localAddress(of listener: borrowing TCPListener) throws(IOError) -> SocketAddress
}
#endif
