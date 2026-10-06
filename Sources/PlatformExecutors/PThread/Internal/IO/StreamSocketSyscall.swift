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
#if canImport(Glibc)
import Glibc
import CPlatformExecutors
#elseif canImport(Musl)
import Musl
import CPlatformExecutors
#elseif canImport(Darwin)
import Darwin
#endif

// The static methods below shadow the C functions of the same name,
// so we have to alias them here.
private let sysBind = bind
private let sysListen = listen
private let sysConnect = connect
private let sysSend = send
private let sysShutdown = shutdown
private let sysClose = close(descriptor:)
#if canImport(Darwin)
private let sysAccept = accept
#else
private let sysAccept4 = CPlatformExecutors_accept4
#endif

/// The non-blocking stream socket syscalls that back the TCP operations.
enum StreamSocketSyscall {
  #if canImport(Glibc) && !os(Android)
  // Glibc imports the socket type and its flags as a C enum,
  // every other platform imports them as plain integers.
  private static var streamSocketType: CInt { CInt(SOCK_STREAM.rawValue) }
  private static var nonBlockingFlag: CInt { CInt(SOCK_NONBLOCK.rawValue) }
  private static var closeOnExecFlag: CInt { CInt(SOCK_CLOEXEC.rawValue) }
  #elseif canImport(Darwin)
  private static var streamSocketType: CInt { CInt(SOCK_STREAM) }
  #else
  private static var streamSocketType: CInt { CInt(SOCK_STREAM) }
  private static var nonBlockingFlag: CInt { CInt(SOCK_NONBLOCK) }
  private static var closeOnExecFlag: CInt { CInt(SOCK_CLOEXEC) }
  #endif

  /// Creates a new non-blocking TCP socket for the given address family.
  ///
  /// - Parameter family: The address family of the socket.
  /// - Returns: The file descriptor of the new socket.
  static func makeSocket(family: CInt) throws(IOError) -> CInt {
    #if canImport(Darwin)
    let fileDescriptor = try retryingIOSyscall(blocking: false) {
      socket(family, Self.streamSocketType, CInt(IPPROTO_TCP))
    }.result

    do {
      // Darwin has no `SOCK_NONBLOCK` and `SOCK_CLOEXEC`, so we have to set
      // both explicitly. It also has no `MSG_NOSIGNAL`, so we disable
      // `SIGPIPE` for the whole socket instead.
      try Self.setNonBlocking(fileDescriptor)
      try Self.setCloseOnExec(fileDescriptor)
      try Self.setSocketOption(fileDescriptor, level: SOL_SOCKET, name: SO_NOSIGPIPE, value: 1)
    } catch {
      // We cannot report both errors, so we drop the error of the close here.
      try? Self.close(fileDescriptor)
      throw error
    }

    return fileDescriptor
    #else
    return try retryingIOSyscall(blocking: false) {
      socket(
        family,
        Self.streamSocketType | Self.nonBlockingFlag | Self.closeOnExecFlag,
        CInt(IPPROTO_TCP)
      )
    }.result
    #endif
  }

  /// Binds the socket to the given address.
  ///
  /// - Parameters:
  ///   - fileDescriptor: The file descriptor of the socket.
  ///   - address: The address to bind to.
  @available(anyAppleOS 26.0, *)
  static func bind(_ fileDescriptor: CInt, to address: SocketAddress) throws(IOError) {
    try address.withUnsafeSockAddress { (sockAddr, length) throws(IOError) -> Void in
      try retryingIOSyscall(blocking: false) {
        sysBind(fileDescriptor, sockAddr, length)
      }
    }
  }

  /// Starts listening for incoming connections on the socket.
  ///
  /// - Parameters:
  ///   - fileDescriptor: The file descriptor of the socket.
  ///   - backlog: The maximum number of connections that the platform queues up.
  static func listen(_ fileDescriptor: CInt, backlog: Int) throws(IOError) {
    try retryingIOSyscall(blocking: false) {
      sysListen(fileDescriptor, CInt(backlog))
    }
  }

  /// Starts connecting the socket to the given address.
  ///
  /// - Parameters:
  ///   - fileDescriptor: The file descriptor of the socket.
  ///   - address: The address to connect to.
  /// - Returns: `true` if the connection was established right away and `false` if it is still in progress. A
  ///   connection that is still in progress completes once the socket becomes writable.
  static func connect(
    _ fileDescriptor: CInt,
    to address: UnsafePointer<sockaddr>,
    addressLength: socklen_t
  ) throws(IOError) -> Bool {
    if sysConnect(fileDescriptor, address, addressLength) == 0 {
      return true
    }

    switch errno {
    case EINPROGRESS:
      return false
    case EINTR:
      // A connect that is interrupted keeps establishing the connection in the
      // background, so we must not retry it here and instead wait for the
      // socket to become writable similar to any other connect that is
      // still in progress.
      return false
    case let errnoCode:
      throw IOError(errnoCode: errnoCode)
    }
  }

  /// Accepts the next connection of a listening socket.
  ///
  /// - Parameter fileDescriptor: The file descriptor of the listening socket.
  /// - Returns: The accepted socket.
  static func accept(_ fileDescriptor: CInt) throws(IOError) -> CInt? {
    let result: IOResult<CInt>
    while true {
      do {
        #if canImport(Darwin)
        result = try retryingIOSyscall(blocking: true) {
          sysAccept(fileDescriptor, nil, nil)
        }
        #else
        result = try retryingIOSyscall(blocking: true) {
          sysAccept4(fileDescriptor, nil, nil, Self.nonBlockingFlag | Self.closeOnExecFlag)
        }
        #endif
        break
      } catch {
        // A connection that is aborted before we accept it fails only
        // itself and not the listening socket, so we move on to the next
        // pending connection. On Darwin this happens when a socket filter
        // drops the connection:
        // https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/kern/uipc_socket.c#L1424-L1477
        //
        // The Linux man page additionally lists network errors of the new
        // connection that should be retried. Linux stopped passing these on
        // to `accept` before 2.6.12, and today it only returns errors of
        // the listening socket or from allocating the new one:
        // https://github.com/torvalds/linux/blob/22430ae5d90ab288b0ee2ad99ae941f4a666b694/net/ipv4/af_inet.c#L783-L802
        // https://github.com/torvalds/linux/blob/22430ae5d90ab288b0ee2ad99ae941f4a666b694/net/ipv4/inet_connection_sock.c#L649-L711
        guard error.code.platformCode == ECONNABORTED else {
          throw error
        }
      }
    }

    guard case .processed(let accepted) = result else {
      return nil
    }

    #if canImport(Darwin)
    do {
      // Darwin has no `accept4` so we need to configure the socket.
      try Self.setNonBlocking(accepted)
      try Self.setCloseOnExec(accepted)
      try Self.setSocketOption(accepted, level: SOL_SOCKET, name: SO_NOSIGPIPE, value: 1)
    } catch {
      // We cannot report both errors, so we drop the error of the close here.
      try? Self.close(accepted)
      throw error
    }
    #endif

    return accepted
  }

  /// Receives bytes from the socket into the given buffer.
  ///
  /// - Parameters:
  ///   - fileDescriptor: The file descriptor of the socket.
  ///   - buffer: The buffer to receive into.
  /// - Returns: The number of bytes received, where zero means that the peer closed its side of the
  ///   connection, or `nil` if receiving would have blocked.
  static func receive(
    _ fileDescriptor: CInt,
    into buffer: UnsafeMutableRawBufferPointer
  ) throws(IOError) -> Int? {
    guard let baseAddress = buffer.baseAddress, buffer.count > 0 else {
      return 0
    }

    let result = try retryingIOSyscall(blocking: true) {
      recv(fileDescriptor, baseAddress, buffer.count, 0)
    }
    guard case .processed(let count) = result else {
      return nil
    }
    return count
  }

  /// Sends the bytes of the given buffer to the socket.
  ///
  /// - Parameters:
  ///   - fileDescriptor: The file descriptor of the socket.
  ///   - buffer: The buffer to send.
  /// - Returns: The number of bytes sent, which can be less than the number of bytes in the buffer, or `nil`
  ///   if sending would have blocked.
  static func send(
    _ fileDescriptor: CInt,
    from buffer: UnsafeRawBufferPointer
  ) throws(IOError) -> Int? {
    guard let baseAddress = buffer.baseAddress, buffer.count > 0 else {
      return 0
    }

    #if canImport(Darwin)
    // `SIGPIPE` is disabled through `SO_NOSIGPIPE` when the socket is created.
    let flags: CInt = 0
    #else
    let flags = CInt(MSG_NOSIGNAL)
    #endif

    let result = try retryingIOSyscall(blocking: true) {
      sysSend(fileDescriptor, baseAddress, buffer.count, flags)
    }
    guard case .processed(let count) = result else {
      return nil
    }
    return count
  }

  /// Shuts down the given directions of the socket.
  ///
  /// - Parameters:
  ///   - fileDescriptor: The file descriptor of the socket.
  ///   - direction: The direction to shut down.
  static func shutdown(
    _ fileDescriptor: CInt,
    direction: SocketShutdownDirection
  ) throws(IOError) {
    let how: CInt =
      switch direction {
      case .read: CInt(SHUT_RD)
      case .write: CInt(SHUT_WR)
      case .readWrite: CInt(SHUT_RDWR)
      }

    try retryingIOSyscall(blocking: false) {
      sysShutdown(fileDescriptor, how)
    }
  }

  /// Closes the socket.
  ///
  /// - Parameter fileDescriptor: The file descriptor of the socket.
  static func close(_ fileDescriptor: CInt) throws(IOError) {
    do {
      try sysClose(fileDescriptor)
    } catch {
      throw IOError(error)
    }
  }

  /// Returns the address that the socket is bound to.
  ///
  /// This is how the address of a socket that was bound to port zero is resolved, since the platform picks
  /// the port in that case.
  ///
  /// - Parameter fileDescriptor: The file descriptor of the socket.
  /// - Returns: The address that the socket is bound to.
  @available(anyAppleOS 26.0, *)
  static func localAddress(_ fileDescriptor: CInt) throws(IOError) -> SocketAddress {
    var storage = sockaddr_storage()
    var length = socklen_t(MemoryLayout<sockaddr_storage>.size)

    let outcome = withUnsafeMutablePointer(to: &storage) { storagePointer in
      storagePointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddr in
        Self.getSocketName(fileDescriptor, into: sockAddr, length: &length)
      }
    }
    if case .failure(let error) = outcome {
      throw error
    }

    guard let address = SocketAddress(storage) else {
      throw IOError(errnoCode: EAFNOSUPPORT)
    }

    return address
  }

  /// Reads the address that the socket is bound to into the given storage.
  private static func getSocketName(
    _ fileDescriptor: CInt,
    into address: UnsafeMutablePointer<sockaddr>,
    length: inout socklen_t
  ) -> Swift.Result<Void, IOError> {
    do {
      try retryingIOSyscall(blocking: false) {
        getsockname(fileDescriptor, address, &length)
      }
      return .success(())
    } catch {
      return .failure(error)
    }
  }

  /// Returns the error that is pending on the socket.
  ///
  /// This is how the result of a connect that was still in progress is retrieved once the socket became
  /// writable.
  ///
  /// - Parameter fileDescriptor: The file descriptor of the socket.
  /// - Returns: The pending `errno` or zero if the socket has no pending error.
  static func pendingError(_ fileDescriptor: CInt) throws(IOError) -> CInt {
    var error: CInt = 0
    var length = socklen_t(MemoryLayout<CInt>.size)

    try retryingIOSyscall(blocking: false) {
      getsockopt(fileDescriptor, SOL_SOCKET, SO_ERROR, &error, &length)
    }

    return error
  }

  /// Allows the socket to bind to an address that is still in its `TIME_WAIT` state.
  ///
  /// - Parameter fileDescriptor: The file descriptor of the socket.
  static func setReuseAddress(_ fileDescriptor: CInt) throws(IOError) {
    try Self.setSocketOption(fileDescriptor, level: SOL_SOCKET, name: SO_REUSEADDR, value: 1)
  }

  private static func setSocketOption(
    _ fileDescriptor: CInt,
    level: CInt,
    name: CInt,
    value: CInt
  ) throws(IOError) {
    var value = value
    try retryingIOSyscall(blocking: false) {
      setsockopt(fileDescriptor, level, name, &value, socklen_t(MemoryLayout<CInt>.size))
    }
  }

  #if canImport(Darwin)
  private static func setNonBlocking(_ fileDescriptor: CInt) throws(IOError) {
    let flags = try retryingIOSyscall(blocking: false) {
      fcntl(fileDescriptor, F_GETFL, 0)
    }.result
    try retryingIOSyscall(blocking: false) {
      fcntl(fileDescriptor, F_SETFL, flags | O_NONBLOCK)
    }
  }

  private static func setCloseOnExec(_ fileDescriptor: CInt) throws(IOError) {
    let flags = try retryingIOSyscall(blocking: false) {
      fcntl(fileDescriptor, F_GETFD, 0)
    }.result
    try retryingIOSyscall(blocking: false) {
      fcntl(fileDescriptor, F_SETFD, flags | FD_CLOEXEC)
    }
  }
  #endif
}
#endif
#endif
