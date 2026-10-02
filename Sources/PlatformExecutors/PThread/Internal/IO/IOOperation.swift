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
#if os(Linux) || os(Android) || os(FreeBSD) || canImport(Darwin) || os(WASI)
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

#if os(WASI)
/// An I/O operation, described independently of any mechanism.
///
/// WASI has no I/O support yet.
enum IOOperation {}
#else
/// An I/O operation, described independently of any mechanism.
///
/// - Important: Every pointer in here has to stay valid until the operation completes or is cancelled. A
/// readiness based mechanism reads the memory when the file descriptor becomes ready and a completion based one lets
/// the kernel read and write it for the whole time the operation is in flight.
enum IOOperation {
  /// Connects a socket to the address in the given storage.
  case connect(socket: CInt, address: UnsafePointer<sockaddr>, addressLength: socklen_t)

  /// Accepts the next connection of a listening socket.
  // TODO: We need address storage to write the accepted addr into.
  case accept(socket: CInt)

  /// Reads from a socket into the given buffer.
  case read(socket: CInt, buffer: UnsafeMutableRawBufferPointer)

  /// Writes the given buffer to a socket.
  case write(socket: CInt, buffer: UnsafeRawBufferPointer)

  /// Shuts down the given directions of a socket.
  case shutdown(socket: CInt, direction: SocketShutdownDirection)

  /// Closes a socket.
  case close(socket: CInt)

  /// The file descriptor that this operation is performed on.
  var fileDescriptor: CInt {
    switch self {
    case .connect(let fileDescriptor, _, _),
      .accept(let fileDescriptor),
      .read(let fileDescriptor, _),
      .write(let fileDescriptor, _),
      .shutdown(let fileDescriptor, _),
      .close(let fileDescriptor):
      return fileDescriptor
    }
  }
}
#endif

/// This is unchecked since we deal with raw pointers. The higher-level contracts of the operation
/// scheduler enusres that this is actually safe.
extension IOOperation: @unchecked Sendable {}

#if !os(WASI)
/// An I/O request.
///
/// This is the safe counterpart of ``IOOperation``. We then lower the individual values to pointers
/// that are pinned to by the operation state to ensure they stay valid for the entire duration.
@available(anyAppleOS 26.0, *)
enum IORequest {
  /// Connects a socket to the given address.
  case connect(socket: CInt, to: SocketAddress)

  /// Accepts the next connection of a listening socket.
  case accept(socket: CInt)

  /// Reads from a socket into the given buffer.
  ///
  /// The buffer is the caller's, so it has to stay valid until the operation completed, which is the contract
  /// of ``TCPSocketOperationScheduler/submitRead(_:state:connection:into:)``.
  case read(socket: CInt, buffer: UnsafeMutableRawBufferPointer)

  /// Writes the given buffer to a socket.
  ///
  /// The buffer is the caller's, so it has to stay valid until the operation completed, which is the contract
  /// of ``TCPSocketOperationScheduler/submitWrite(_:state:connection:from:)``.
  case write(socket: CInt, buffer: UnsafeRawBufferPointer)

  /// Shuts down the given directions of a socket.
  case shutdown(socket: CInt, direction: SocketShutdownDirection)

  /// Closes a socket.
  case close(socket: CInt)
}

@available(anyAppleOS 26.0, *)
extension IORequest {
  /// The address that the operation needs to outlive its submission, if it has one.
  var address: SocketAddress? {
    switch self {
    case .connect(_, let address):
      return address
    case .accept, .read, .write, .shutdown, .close:
      return nil
    }
  }
}
#endif

/// The identity of one submitted operation.
struct IOOperationID: Hashable, Sendable {
  /// The underlying value of this identity.
  var rawValue: UInt

  /// Creates a new identity.
  ///
  /// - Parameter rawValue: The underlying value of the identity.
  init(rawValue: UInt) {
    self.rawValue = rawValue
  }
}
#endif
#endif
