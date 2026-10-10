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
  package func connect(to address: SocketAddress) async throws(IOError) -> TCPConnection {
    let socket = try StreamSocketSyscall.makeSocket(family: address.family)

    // The kernel reads the address while we are suspended, so it lives in
    // storage that outlives the operation.
    return try await withTemporaryAllocation(of: sockaddr_storage.self, capacity: 1) {
      storage async throws(IOError) -> TCPConnection in
      storage.append(sockaddr_storage())
      var addresses = storage.mutableSpan
      let operation = addresses.withUnsafeMutableBufferPointer { buffer in
        let addressLength = address.write(into: &buffer[0])
        return IOOperation.connect(
          socket: socket,
          address: UnsafeRawPointer(buffer.baseAddress!).assumingMemoryBound(to: sockaddr.self),
          addressLength: addressLength
        )
      }
      return try await self.perform(operation) { continuation in
        .connection(continuation, socket: socket, executorIndex: self.poolIndex)
      }
    }
  }

  package func listen(on address: SocketAddress, backlog: Int) async throws(IOError) -> TCPListener {
    let socket = try StreamSocketSyscall.makeSocket(family: address.family)
    do {
      try StreamSocketSyscall.setReuseAddress(socket)
      try StreamSocketSyscall.bind(socket, to: address)
      try StreamSocketSyscall.listen(socket, backlog: backlog)
    } catch {
      try? StreamSocketSyscall.close(socket)
      throw error
    }
    return TCPListener(fileDescriptor: socket, executorIndex: self.poolIndex)
  }

  package func accept(listener: borrowing TCPListener) async throws(IOError) -> TCPConnection {
    try await self.perform(.accept(socket: listener.fileDescriptor)) { continuation in
      .acceptedConnection(continuation, executorIndex: self.poolIndex)
    }
  }

  package func read(
    connection: borrowing TCPConnection,
    into buffer: inout OutputRawSpan
  ) async throws(IOError) -> Int {
    // The bytes are read into the free capacity of the buffer, which stays
    // alive while we are suspended since we hold the access to it.
    let freeCapacity = buffer.withUnsafeMutableBytes { bytes, initializedCount in
      UnsafeMutableRawBufferPointer(rebasing: bytes[initializedCount...])
    }

    let count = try await self.perform(.read(socket: connection.fileDescriptor, buffer: freeCapacity)) {
      continuation in
      .byteCount(continuation)
    }

    // The kernel wrote into the free capacity of the buffer so we have to
    // update the initialized count now.
    buffer.withUnsafeMutableBytes { _, initializedCount in
      initializedCount += count
    }
    return count
  }

  package func write(connection: borrowing TCPConnection, from buffer: RawSpan) async throws(IOError) -> Int {
    let bytes = buffer.withUnsafeBytes { $0 }
    return try await self.perform(.write(socket: connection.fileDescriptor, buffer: bytes)) { continuation in
      .byteCount(continuation)
    }
  }

  package func shutdown(
    connection: borrowing TCPConnection,
    direction: SocketShutdownDirection
  ) async throws(IOError) {
    try await self.perform(.shutdown(socket: connection.fileDescriptor, direction: direction)) { continuation in
      .void(continuation)
    }
  }

  package func close(connection: consuming TCPConnection) async throws(IOError) {
    let fileDescriptor = connection.takeFileDescriptor()
    try await self.perform(.close(socket: fileDescriptor)) { continuation in
      .void(continuation)
    }
  }

  package func close(listener: consuming TCPListener) async throws(IOError) {
    let fileDescriptor = listener.takeFileDescriptor()
    try await self.perform(.close(socket: fileDescriptor)) { continuation in
      .void(continuation)
    }
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
