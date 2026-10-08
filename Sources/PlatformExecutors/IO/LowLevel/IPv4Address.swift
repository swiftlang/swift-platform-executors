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
/// An IPv4 address.
@available(anyAppleOS 26.0, *)
public struct IPv4Address: Sendable, Hashable {
  /// The number of bytes in an IPv4 address.
  public static var byteCount: Int { 4 }

  /// The wildcard address `0.0.0.0`.
  public static var any: IPv4Address { IPv4Address(0, 0, 0, 0) }

  /// The loopback address `127.0.0.1`.
  public static var loopback: IPv4Address { IPv4Address(127, 0, 0, 1) }

  /// The broadcast address `255.255.255.255`.
  public static var broadcast: IPv4Address { IPv4Address(255, 255, 255, 255) }

  /// The bytes of the address in network byte order.
  ///
  /// The address `127.0.0.1` is stored as `[127, 0, 0, 1]`.
  public var bytes: InlineArray<4, UInt8>

  /// Creates an address from its bytes in network byte order.
  ///
  /// - Parameter bytes: The bytes of the address in network byte order.
  public init(bytes: InlineArray<4, UInt8>) {
    self.bytes = bytes
  }

  /// Creates an address from its four bytes in network byte order.
  ///
  /// - Parameters:
  ///   - byte0: The most significant byte of the address.
  ///   - byte1: The second most significant byte of the address.
  ///   - byte2: The third most significant byte of the address.
  ///   - byte3: The least significant byte of the address.
  public init(_ byte0: UInt8, _ byte1: UInt8, _ byte2: UInt8, _ byte3: UInt8) {
    self.bytes = [byte0, byte1, byte2, byte3]
  }

  public static func == (lhs: IPv4Address, rhs: IPv4Address) -> Bool {
    for index in lhs.bytes.indices where lhs.bytes[index] != rhs.bytes[index] {
      return false
    }
    return true
  }

  public func hash(into hasher: inout Hasher) {
    for index in self.bytes.indices {
      hasher.combine(self.bytes[index])
    }
  }
}
#endif
