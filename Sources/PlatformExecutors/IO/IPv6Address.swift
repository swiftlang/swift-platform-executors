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
/// An IPv6 address.
@available(anyAppleOS 26.0, *)
public struct IPv6Address: Sendable, Hashable {
  /// The number of bytes in an IPv6 address.
  public static var byteCount: Int { 16 }

  /// The wildcard address `::`.
  public static var any: IPv6Address { IPv6Address(bytes: .init(repeating: 0)) }

  /// The loopback address `::1`.
  public static var loopback: IPv6Address {
    var bytes = InlineArray<16, UInt8>(repeating: 0)
    bytes[15] = 1
    return IPv6Address(bytes: bytes)
  }

  /// The bytes of the address in network byte order.
  ///
  /// The address `::1` is stored as `[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]`.
  public var bytes: InlineArray<16, UInt8>

  /// Creates an address from its bytes in network byte order.
  ///
  /// - Parameter bytes: The bytes of the address in network byte order.
  public init(bytes: InlineArray<16, UInt8>) {
    self.bytes = bytes
  }

  public static func == (lhs: IPv6Address, rhs: IPv6Address) -> Bool {
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
