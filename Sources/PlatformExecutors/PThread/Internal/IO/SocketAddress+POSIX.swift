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

@available(anyAppleOS 26.0, *)
extension SocketAddress {
  /// The address family of this address.
  var family: CInt {
    switch self {
    case .v4:
      AF_INET
    case .v6:
      AF_INET6
    }
  }

  /// Calls the given body with the POSIX representation of this address.
  ///
  /// - Parameter body: The body to call with the address and its length.
  /// - Returns: The result of the body.
  func withUnsafeSockAddress<Result: ~Copyable, Failure: Error>(
    _ body: (UnsafePointer<sockaddr>, socklen_t) throws(Failure) -> Result
  ) throws(Failure) -> Result {
    switch self {
    case .v4(let v4):
      var address = sockaddr_in()
      #if canImport(Darwin)
      address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
      #endif
      address.sin_family = sa_family_t(AF_INET)
      address.sin_port = v4.port.bigEndian
      withUnsafeMutableBytes(of: &address.sin_addr) { destination in
        for index in v4.address.bytes.indices {
          destination[index] = v4.address.bytes[index]
        }
      }
      return try Self.withUnsafeSockAddress(of: &address, body)

    case .v6(let v6):
      var address = sockaddr_in6()
      #if canImport(Darwin)
      address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
      #endif
      address.sin6_family = sa_family_t(AF_INET6)
      address.sin6_port = v6.port.bigEndian
      address.sin6_scope_id = v6.scopeID
      withUnsafeMutableBytes(of: &address.sin6_addr) { destination in
        for index in v6.address.bytes.indices {
          destination[index] = v6.address.bytes[index]
        }
      }
      return try Self.withUnsafeSockAddress(of: &address, body)
    }
  }

  /// Calls the body with the given concrete address viewed as a `sockaddr`.
  ///
  /// Every socket syscall takes an address as a `sockaddr` and a length, so the concrete address has to be
  /// punned. The bytes are viewed untyped rather than rebound: a `sockaddr` is 16 bytes and a `sockaddr_in6` is
  /// 28, so rebinding would claim one `sockaddr` while the kernel goes on to read the full length. Taking the
  /// length from the same buffer as the pointer also keeps the two from disagreeing.
  private static func withUnsafeSockAddress<Address, Result: ~Copyable, Failure: Error>(
    of address: inout Address,
    _ body: (UnsafePointer<sockaddr>, socklen_t) throws(Failure) -> Result
  ) throws(Failure) -> Result {
    // `withUnsafeBytes` is only rethrowing, so it does not carry the thrown type through and the error has to be
    // cast back. Only `body` can throw here, so the cast cannot fail.
    do {
      return try withUnsafeBytes(of: &address) { bytes in
        try body(
          bytes.baseAddress!.assumingMemoryBound(to: sockaddr.self),
          socklen_t(bytes.count)
        )
      }
    } catch {
      throw error as! Failure
    }
  }

  /// Writes the POSIX representation of this address into the given storage.
  ///
  /// A completion based mechanism reads the address while the caller is suspended, so it has to live in memory
  /// that outlives the submission rather than on the stack of the submitting function.
  ///
  /// - Parameter storage: The storage to write the address into.
  /// - Returns: The length of the address that was written.
  func write(into storage: inout sockaddr_storage) -> socklen_t {
    self.withUnsafeSockAddress { address, length in
      withUnsafeMutableBytes(of: &storage) { destination in
        destination.copyMemory(
          from: UnsafeRawBufferPointer(start: UnsafeRawPointer(address), count: Int(length))
        )
      }
      return length
    }
  }

  /// Creates an address from its POSIX representation.
  ///
  /// - Parameter storage: The POSIX representation of the address.
  /// - Returns: `nil` if the address family is neither `AF_INET` nor `AF_INET6`.
  init?(_ storage: sockaddr_storage) {
    switch CInt(storage.ss_family) {
    case AF_INET:
      // `load` copies the address out. The alignment it requires is satisfied
      // because `sockaddr_storage` is aligned for every address it can hold.
      let address = withUnsafeBytes(of: storage) { $0.load(as: sockaddr_in.self) }
      let bytes = withUnsafeBytes(of: address.sin_addr) { source in
        InlineArray<4, UInt8> { source[$0] }
      }
      self = .v4(
        V4(
          address: IPv4Address(bytes: bytes),
          port: UInt16(bigEndian: address.sin_port)
        )
      )

    case AF_INET6:
      let address = withUnsafeBytes(of: storage) { $0.load(as: sockaddr_in6.self) }
      let bytes = withUnsafeBytes(of: address.sin6_addr) { source in
        InlineArray<16, UInt8> { source[$0] }
      }
      self = .v6(
        V6(
          address: IPv6Address(bytes: bytes),
          port: UInt16(bigEndian: address.sin6_port),
          scopeID: address.sin6_scope_id
        )
      )

    default:
      return nil
    }
  }
}
#endif
#endif
