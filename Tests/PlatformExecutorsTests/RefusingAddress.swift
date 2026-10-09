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
#if os(Linux) || os(FreeBSD) || canImport(Darwin)
@_spi(ExperimentalScheduling) @_spi(ConcurrencyExecutors) @_spi(ExperimentalCustomExecutors) import PlatformExecutors

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// Runs the body with a loopback address that refuses connections.
///
/// The port is bound by a socket that never listens, so connecting to it is refused. Unlike the port of a
/// listener that was closed again, no other test that runs in parallel can bind the port while the body runs.
///
/// - Parameter body: The body to run with the address.
@available(anyAppleOS 27.0, *)
func withRefusingAddress(
  _ body: (SocketAddress) async throws -> Void
) async throws {
  #if canImport(Glibc)
  let socketType = CInt(SOCK_STREAM.rawValue)
  #else
  let socketType = SOCK_STREAM
  #endif
  let fileDescriptor = socket(AF_INET, socketType, 0)
  guard fileDescriptor >= 0 else {
    throw RefusingAddressError(function: "socket", errnoCode: errno)
  }
  defer {
    close(fileDescriptor)
  }

  var address = sockaddr_in()
  #if canImport(Darwin)
  address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
  #endif
  address.sin_family = sa_family_t(AF_INET)
  address.sin_addr.s_addr = in_addr_t(INADDR_LOOPBACK).bigEndian
  address.sin_port = 0
  var length = socklen_t(MemoryLayout<sockaddr_in>.size)

  let failedFunction = withUnsafeMutablePointer(to: &address) { pointer -> String? in
    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address -> String? in
      if bind(fileDescriptor, address, length) != 0 {
        return "bind"
      }
      // The platform picks the port while binding, so we read it back here.
      if getsockname(fileDescriptor, address, &length) != 0 {
        return "getsockname"
      }
      return nil
    }
  }
  if let function = failedFunction {
    throw RefusingAddressError(function: function, errnoCode: errno)
  }

  try await body(.v4(SocketAddress.V4(address: .loopback, port: UInt16(bigEndian: address.sin_port))))
}

/// Reserving a port for ``withRefusingAddress(_:)`` failed.
struct RefusingAddressError: Error {
  /// The function that failed.
  var function: String

  /// The error code that the function failed with.
  var errnoCode: CInt
}
#endif
#endif
