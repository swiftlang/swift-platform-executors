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

  /// Creates a new socket and connects it to the given address.
  ///
  /// - Parameter address: The address to connect to.
  /// - Returns: The connected socket.
  func connect(to address: SocketAddress) async throws(IOError) -> TCPConnection

  /// Creates a new socket, binds it to the given address and starts listening for incoming connections.
  ///
  /// - Parameters:
  ///   - address: The address to bind the socket to.
  ///   - backlog: The maximum number of connections the platform queues up
  ///     before refusing new ones.
  /// - Returns: The listening socket.
  func listen(on address: SocketAddress, backlog: Int) async throws(IOError) -> TCPListener

  /// Accepts the next incoming connection of a listening socket.
  ///
  /// - Parameter listener: The listening socket to accept a connection from.
  /// - Returns: The accepted socket.
  func accept(listener: borrowing TCPListener) async throws(IOError) -> TCPConnection

  /// Reads once from a socket into the free capacity of the given buffer.
  ///
  /// The bytes are appended to the buffer. A read can return fewer bytes than the free capacity of the
  /// buffer.
  ///
  /// - Parameters:
  ///   - connection: The socket to read from.
  ///   - buffer: The buffer to read into.
  /// - Returns: The number of bytes read. Zero indicates that the peer closed its side of the connection, or
  ///   that the buffer has no free capacity.
  func read(connection: borrowing TCPConnection, into buffer: inout OutputRawSpan) async throws(IOError) -> Int

  /// Writes the given buffer to a socket.
  ///
  /// - Parameters:
  ///   - connection: The socket to write to.
  ///   - buffer: The buffer to write from.
  /// - Returns: The number of bytes written. This can be less than the number of bytes in the buffer.
  func write(connection: borrowing TCPConnection, from buffer: RawSpan) async throws(IOError) -> Int

  /// Shuts down one or both directions of a socket.
  ///
  /// Shutting down the write direction sends a `FIN` to the peer, which
  /// observes it as the end of the stream once it has received all data that is
  /// still in flight. The socket can still be read from afterwards, which is
  /// how a protocol signals that it is done sending without discarding what the
  /// peer is still sending.
  ///
  /// - Parameters:
  ///   - connection: The socket to shut down.
  ///   - direction: The direction to shut down.
  func shutdown(connection: borrowing TCPConnection, direction: SocketShutdownDirection) async throws(IOError)

  /// Closes a socket.
  ///
  /// - Parameter connection: The socket to close.
  func close(connection: consuming TCPConnection) async throws(IOError)

  /// Closes a listening socket.
  ///
  /// - Parameter listener: The listening socket to close.
  func close(listener: consuming TCPListener) async throws(IOError)

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
