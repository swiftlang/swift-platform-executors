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
/// The address of a socket endpoint.
@available(anyAppleOS 26.0, *)
public enum SocketAddress: Sendable, Hashable {
  /// An IPv4 socket address.
  public struct V4: Sendable, Hashable {
    /// The IPv4 address.
    public var address: IPv4Address

    /// The port in host byte order.
    public var port: UInt16

    /// Creates a new IPv4 socket address.
    ///
    /// - Parameters:
    ///   - address: The IPv4 address.
    ///   - port: The port in host byte order.
    public init(address: IPv4Address, port: UInt16) {
      self.address = address
      self.port = port
    }
  }

  /// An IPv6 socket address.
  public struct V6: Sendable, Hashable {
    /// The IPv6 address.
    public var address: IPv6Address

    /// The port in host byte order.
    public var port: UInt16

    /// The identifier of the interface that the address is scoped to.
    ///
    /// This is only meaningful for link-local addresses and is zero otherwise.
    public var scopeID: UInt32

    /// Creates a new IPv6 socket address.
    ///
    /// - Parameters:
    ///   - address: The IPv6 address.
    ///   - port: The port in host byte order.
    ///   - scopeID: The identifier of the interface that the address is scoped to.
    public init(address: IPv6Address, port: UInt16, scopeID: UInt32 = 0) {
      self.address = address
      self.port = port
      self.scopeID = scopeID
    }
  }

  /// An IPv4 socket address.
  case v4(V4)

  /// An IPv6 socket address.
  case v6(V6)

  /// The port of the address in host byte order.
  public var port: UInt16 {
    switch self {
    case .v4(let address): address.port
    case .v6(let address): address.port
    }
  }
}
#endif
