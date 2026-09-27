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
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

// The static methods below shadow the C functions of the same name,
// so we have to alias them here.
private let sysBind = bind
private let sysListen = listen
private let sysClose = close(descriptor:)

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
