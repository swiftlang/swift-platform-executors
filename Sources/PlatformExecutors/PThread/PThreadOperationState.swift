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

/// The state that the PThread based executors need per in-flight operation.
// TODO: When we switch to async methods this is gone
@available(anyAppleOS 27.0, *)
public struct PThreadOperationState: ~Copyable {
  /// The address that an operation connects to, or that an accept writes the peer's address into.
  internal var address = sockaddr_storage()

  /// The length of ``address``.
  internal var addressLength = socklen_t(MemoryLayout<sockaddr_storage>.size)

  /// Creates the state of an operation.
  ///
  /// - Parameter address: The address that the operation needs to outlive its submission, if it has one. The
  ///   kernel reads this while the submitter is suspended, so it is copied in here rather than pointed at on
  ///   the submitter's stack.
  internal init(address: SocketAddress?) {
    if let address {
      self.addressLength = address.write(into: &self.address)
    }
  }
}
#endif
#endif
