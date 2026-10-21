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
@unsafe
enum IOOperation {}
#else
/// An I/O operation, described independently of any mechanism.
///
/// - Important: Every pointer in here has to stay valid until the operation completes or is cancelled. A
/// readiness based mechanism reads the memory when the file descriptor becomes ready and a completion based one lets
/// the kernel read and write it for the whole time the operation is in flight.
@unsafe
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

  /// Closes a file descriptor.
  case close(fileDescriptor: CInt)

  /// Opens the file at the given path, relative to the current working directory.
  case openFile(path: UnsafePointer<CChar>, flags: CInt, permissions: mode_t)

  /// Reads from the given offset of a file into the given buffer.
  case readFile(file: CInt, buffer: UnsafeMutableRawBufferPointer, offset: Int64)

  /// Writes the given buffer to the given offset of a file.
  case writeFile(file: CInt, buffer: UnsafeRawBufferPointer, offset: Int64)

  /// The file descriptor that this operation is performed on.
  var fileDescriptor: CInt {
    switch unsafe self {
    case .openFile:
      fatalError("The operation creates its file descriptor.")
    case .readFile(let fileDescriptor, _, _),
      .writeFile(let fileDescriptor, _, _):
      return fileDescriptor
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

/// This is unchecked since we deal with raw pointers. The operations are performed by `async` methods that
/// keep the memory alive until the operation completed, which ensures that this is actually safe.
extension IOOperation: @unchecked Sendable {}

extension IOOperation {
  /// The number of in-flight operations and events per wait that we initially reserve
  /// to reduce ramp up allocations.
  static var reservedCapacity: Int { 1024 }
}

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
