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

/// Runs the body with a message header that describes the buffer and names the storage for the address.
///
/// - Parameters:
///   - buffer: The buffer that holds or receives the bytes of the datagram.
///   - address: The storage for the address, which holds the destination of a send or receives the sender.
///   - addressLength: The length of the address, or the capacity for receiving one.
///   - body: The closure to invoke with the header.
/// - Returns: Whatever is returned by `body`.
private nonisolated(nonsending) func withDatagramMessage<R, E: Error>(
  buffer: UnsafeMutableRawBufferPointer,
  address: inout sockaddr_storage,
  addressLength: socklen_t,
  _ body: nonisolated(nonsending) (UnsafeMutablePointer<msghdr>) async throws(E) -> R
) async throws(E) -> R {
  var header = unsafe msghdr()
  var vector = unsafe iovec()
  unsafe vector.iov_base = buffer.baseAddress
  unsafe vector.iov_len = buffer.count
  return try await unsafe withUnsafeMutablePointer(to: &address) { address async throws(E) -> R in
    try await unsafe withUnsafeMutablePointer(to: &vector) { vector async throws(E) -> R in
      // Some platforms reject a message that has a name of length zero so we use nil instead.
      unsafe header.msg_name = addressLength == 0 ? nil : UnsafeMutableRawPointer(address)
      unsafe header.msg_namelen = addressLength
      unsafe header.msg_iov = vector
      unsafe header.msg_iovlen = 1
      return try await unsafe withUnsafeMutablePointer(to: &header) { header async throws(E) -> R in
        try await unsafe body(header)
      }
    }
  }
}

// MARK: - UDP socket handles

@available(anyAppleOS 27.0, *)
extension PThreadExecutor {
  /// A UDP socket of a ``PThreadExecutor``.
  package typealias UDPSocket = PThreadUDPSocket
}

// MARK: - UDP socket operations

@available(anyAppleOS 27.0, *)
extension PThreadExecutor: UDPSocketOperationScheduler {
  package func bind(to address: SocketAddress) async throws(IOError) -> UDPSocket {
    let socket = try SocketSyscall.makeSocket(family: address.family, kind: .datagram)
    do {
      try SocketSyscall.bind(socket, to: address)
    } catch {
      try? SocketSyscall.close(socket)
      throw error
    }
    return UDPSocket(fileDescriptor: socket)
  }

  package func connectUDP(to address: SocketAddress) async throws(IOError) -> UDPSocket {
    let socket = try SocketSyscall.makeSocket(family: address.family, kind: .datagram)
    do {
      try Self.connect(socket, to: address)
    } catch {
      try? SocketSyscall.close(socket)
      throw error
    }
    return UDPSocket(fileDescriptor: socket)
  }

  package func connectUDP(socket: borrowing UDPSocket, to address: SocketAddress) async throws(IOError) {
    try Self.connect(socket.fileDescriptor, to: address)
  }

  package func receive(
    socket: borrowing UDPSocket,
    into buffer: inout OutputRawSpan
  ) async throws(IOError) -> (count: Int, sender: SocketAddress) {
    let (count, sender) = try await self.receiveDatagram(
      on: socket.fileDescriptor,
      into: &buffer,
      addressCapacity: socklen_t(MemoryLayout<sockaddr_storage>.size)
    )
    guard let sender = SocketAddress(sender) else {
      throw IOError(errnoCode: EAFNOSUPPORT)
    }
    return (count, sender)
  }

  package func read(socket: borrowing UDPSocket, into buffer: inout OutputRawSpan) async throws(IOError) -> Int {
    try await self.receiveDatagram(on: socket.fileDescriptor, into: &buffer, addressCapacity: 0).count
  }

  package func send(
    socket: borrowing UDPSocket,
    from buffer: RawSpan,
    to address: SocketAddress
  ) async throws(IOError) -> Int {
    try await self.sendDatagram(on: socket.fileDescriptor, from: buffer, to: address)
  }

  package func write(socket: borrowing UDPSocket, from buffer: RawSpan) async throws(IOError) -> Int {
    try await self.sendDatagram(on: socket.fileDescriptor, from: buffer, to: nil)
  }

  /// Receives one datagram into the free capacity of the buffer.
  ///
  /// - Parameters:
  ///   - fileDescriptor: The file descriptor of the socket.
  ///   - buffer: The buffer to receive into.
  ///   - addressCapacity: The capacity for the address of the sender, which is zero if it is not wanted.
  private func receiveDatagram(
    on fileDescriptor: CInt,
    into buffer: inout OutputRawSpan,
    addressCapacity: socklen_t
  ) async throws(IOError) -> (count: Int, sender: sockaddr_storage) {
    // The bytes are received into the free capacity of the buffer, which stays
    // alive while we are suspended since we hold the access to it.
    let freeCapacity = unsafe buffer.withUnsafeMutableBytes { bytes, initializedCount in
      unsafe UnsafeMutableRawBufferPointer(rebasing: bytes[initializedCount...])
    }

    // The kernel writes the sender's address while we are suspended.
    var sender = sockaddr_storage()
    let count = try await unsafe withDatagramMessage(
      buffer: freeCapacity,
      address: &sender,
      addressLength: addressCapacity
    ) { header async throws(IOError) -> Int in
      try await unsafe self.perform(
        .receiveMessage(socket: fileDescriptor, message: header)
      ) { continuation in
        .byteCount(continuation)
      }
    }

    // The kernel wrote into the free capacity of the buffer so we have to
    // update the initialized count now.
    unsafe buffer.withUnsafeMutableBytes { _, initializedCount in
      initializedCount += count
    }
    return (count, sender)
  }

  /// Sends the buffer as one datagram.
  ///
  /// - Parameters:
  ///   - fileDescriptor: The file descriptor of the socket.
  ///   - buffer: The bytes of the datagram.
  ///   - address: The address to send to, or `nil` to send to the peer that the socket is connected to.
  private func sendDatagram(
    on fileDescriptor: CInt,
    from buffer: RawSpan,
    to address: SocketAddress?
  ) async throws(IOError) -> Int {
    let bytes = buffer.withUnsafeBytes { unsafe $0 }

    var destination = sockaddr_storage()
    let addressLength = address?.write(into: &destination) ?? 0
    return try await unsafe withDatagramMessage(
      buffer: UnsafeMutableRawBufferPointer(mutating: bytes),
      address: &destination,
      addressLength: addressLength
    ) { header async throws(IOError) -> Int in
      try await unsafe self.perform(
        .sendMessage(socket: fileDescriptor, message: header)
      ) { continuation in
        .byteCount(continuation)
      }
    }
  }

  /// Connects the socket to the address.
  ///
  /// Connecting a datagram socket only records the peer, so it completes right away.
  private static func connect(_ fileDescriptor: CInt, to address: SocketAddress) throws(IOError) {
    try unsafe address.withUnsafeSockAddress { (sockAddr, length) throws(IOError) -> Void in
      _ = try unsafe SocketSyscall.connect(fileDescriptor, to: sockAddr, addressLength: length)
    }
  }

  // TODO: Implement the operations that lease buffers.
  package func receive(socket: borrowing UDPSocket) async throws(IOError) -> ReceivedDatagram {
    fatalError("Leasing buffers is not implemented yet")
  }

  package func read(socket: borrowing UDPSocket) async throws(IOError) -> LeasedBuffer {
    fatalError("Leasing buffers is not implemented yet")
  }

  package func close(socket: consuming UDPSocket) async throws(IOError) {
    let fileDescriptor = socket.takeFileDescriptor()
    try await unsafe self.perform(.close(fileDescriptor: fileDescriptor)) { continuation in
      .void(continuation)
    }
  }

  /// Returns the address that the socket is bound to.
  ///
  /// This is how a socket that was bound to port zero reports the port the platform picked for it.
  ///
  /// - Parameter socket: The socket to return the address of.
  /// - Returns: The address that the socket is bound to.
  package func localAddress(of socket: borrowing UDPSocket) throws(IOError) -> SocketAddress {
    try SocketSyscall.localAddress(socket.fileDescriptor)
  }

  /// Returns the address of the peer that the connected socket is connected to.
  ///
  /// - Parameter socket: The connected socket to return the peer of.
  /// - Returns: The address of the peer.
  package func remoteAddress(of socket: borrowing UDPSocket) throws(IOError) -> SocketAddress {
    try SocketSyscall.peerAddress(socket.fileDescriptor)
  }
}
#endif
#endif
