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

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

// MARK: - TCP socket handles

@available(anyAppleOS 27.0, *)
extension PThreadExecutor {
  /// A connected TCP socket of a ``PThreadExecutor``.
  package typealias TCPConnection = PThreadTCPConnection

  /// A listening TCP socket of a ``PThreadExecutor``.
  package typealias TCPListener = PThreadTCPListener
}

// MARK: - TCP socket operations

@available(anyAppleOS 27.0, *)
extension PThreadExecutor: TCPSocketOperationScheduler {
  package func submitConnect(
    _ continuation: consuming Continuation<TCPConnection, IOError>,
    state: inout OutputSpan<OperationState>,
    to address: SocketAddress
  ) -> OperationRegistration {
    let socket: CInt
    do {
      socket = try StreamSocketSyscall.makeSocket(family: address.family)
    } catch {
      continuation.resume(throwing: error)
      return Self.completedRegistration
    }

    return self.submit(
      .connection(continuation, socket: socket, executorIndex: self.poolIndex),
      request: .connect(socket: socket, to: address),
      state: &state
    )
  }

  package func submitListen(
    _ continuation: consuming Continuation<TCPListener, IOError>,
    state: inout OutputSpan<OperationState>,
    on address: SocketAddress,
    backlog: Int
  ) -> OperationRegistration {
    let socket: CInt
    do {
      socket = try StreamSocketSyscall.makeSocket(family: address.family)
    } catch {
      continuation.resume(throwing: error)
      return Self.completedRegistration
    }

    do {
      try StreamSocketSyscall.setReuseAddress(socket)
      try StreamSocketSyscall.bind(socket, to: address)
      try StreamSocketSyscall.listen(socket, backlog: backlog)
    } catch {
      try? StreamSocketSyscall.close(socket)
      continuation.resume(throwing: error)
      return Self.completedRegistration
    }

    continuation.resume(returning: TCPListener(fileDescriptor: socket, executorIndex: self.poolIndex))
    return Self.completedRegistration
  }

  package func submitAccept(
    _ continuation: consuming Continuation<TCPConnection, IOError>,
    state: inout OutputSpan<OperationState>,
    listener: borrowing TCPListener
  ) -> OperationRegistration {
    self.submit(
      .acceptedConnection(continuation, executorIndex: self.poolIndex),
      request: .accept(socket: listener.fileDescriptor),
      state: &state
    )
  }

  package func submitRead(
    _ continuation: consuming Continuation<Int, IOError>,
    state: inout OutputSpan<OperationState>,
    connection: borrowing TCPConnection,
    into buffer: inout OutputRawSpan
  ) -> OperationRegistration {
    // The bytes are read into the free capacity of the buffer. The operation
    // completes afterwards when we have no access to the output span anymore.
    // TODO: We should try out async entrypoints for the submit methods.
    let freeCapacity = buffer.withUnsafeMutableBytes { bytes, initializedCount in
      UnsafeMutableRawBufferPointer(rebasing: bytes[initializedCount...])
    }

    return self.submit(
      .byteCount(continuation),
      request: .read(socket: connection.fileDescriptor, buffer: freeCapacity),
      state: &state
    )
  }

  package func submitWrite(
    _ continuation: consuming Continuation<Int, IOError>,
    state: inout OutputSpan<OperationState>,
    connection: borrowing TCPConnection,
    from buffer: RawSpan
  ) -> OperationRegistration {
    let bytes = buffer.withUnsafeBytes { $0 }

    return self.submit(
      .byteCount(continuation),
      request: .write(socket: connection.fileDescriptor, buffer: bytes),
      state: &state
    )
  }

  package func submitShutdown(
    _ continuation: consuming Continuation<Void, IOError>,
    state: inout OutputSpan<OperationState>,
    connection: borrowing TCPConnection,
    direction: SocketShutdownDirection
  ) -> OperationRegistration {
    self.submit(
      .void(continuation),
      request: .shutdown(socket: connection.fileDescriptor, direction: direction),
      state: &state
    )
  }

  package func submitClose(
    _ continuation: consuming Continuation<Void, IOError>,
    state: inout OutputSpan<OperationState>,
    connection: consuming TCPConnection
  ) -> OperationRegistration {
    let fileDescriptor = connection.takeFileDescriptor()
    return self.submit(
      .void(continuation),
      request: .close(socket: fileDescriptor),
      state: &state
    )
  }

  package func submitClose(
    _ continuation: consuming Continuation<Void, IOError>,
    state: inout OutputSpan<OperationState>,
    listener: consuming TCPListener
  ) -> OperationRegistration {
    let fileDescriptor = listener.takeFileDescriptor()
    return self.submit(
      .void(continuation),
      request: .close(socket: fileDescriptor),
      state: &state
    )
  }

  /// Returns the local address of the connection.
  ///
  /// - Parameter connection: The connection to return the local address of.
  /// - Returns: The address that the connection is bound to locally.
  package func localAddress(of connection: borrowing TCPConnection) throws(IOError) -> SocketAddress {
    try StreamSocketSyscall.localAddress(connection.fileDescriptor)
  }

  /// Returns the address that the listening socket is bound to.
  ///
  /// This is how a listener that was bound to port zero reports the port the platform picked for it.
  ///
  /// - Parameter listener: The listening socket to return the address of.
  /// - Returns: The address that the listening socket is bound to.
  package func localAddress(of listener: borrowing TCPListener) throws(IOError) -> SocketAddress {
    try StreamSocketSyscall.localAddress(listener.fileDescriptor)
  }
}
#endif
#endif
