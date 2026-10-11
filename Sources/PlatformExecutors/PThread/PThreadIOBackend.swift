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

#if os(Linux) || os(Android) || os(FreeBSD) || canImport(Darwin) || os(WASI)
/// The mechanism that the threads of a PThread based executor wait for events and perform their I/O with.
public struct PThreadIOBackend: Sendable, Hashable, CustomStringConvertible {
  /// The mechanisms that a configuration can select.
  enum Kind: Hashable {
    case platformDefault
    #if canImport(Darwin)
    case kqueue
    #elseif canImport(Glibc)
    case epoll
    #if ExperimentalIOUring
    case ioUring
    #endif
    #endif
  }

  /// The mechanism that this configuration selects.
  let kind: Kind

  /// The default mechanism to use on a platform.
  ///
  /// This will be decided at runtime depending on platform and kernel version.
  public static var platformDefault: Self {
    Self(kind: .platformDefault)
  }

  #if canImport(Darwin)
  /// The `kqueue` mechanism.
  public static var kqueue: Self {
    Self(kind: .kqueue)
  }
  #elseif canImport(Glibc)
  /// The `epoll` mechanism.
  public static var epoll: Self {
    Self(kind: .epoll)
  }

  #if ExperimentalIOUring
  /// The `io_uring` mechanism.
  ///
  /// - Important: Creating an executor with it traps if the kernel does not allow creating a ring. Use
  ///   ``platformDefault`` to fall back to `epoll` instead.
  public static var ioUring: Self {
    Self(kind: .ioUring)
  }
  #endif
  #endif

  public var description: String {
    switch self.kind {
    case .platformDefault:
      return "platformDefault"
    #if canImport(Darwin)
    case .kqueue:
      return "kqueue"
    #elseif canImport(Glibc)
    case .epoll:
      return "epoll"
    #if ExperimentalIOUring
    case .ioUring:
      return "ioUring"
    #endif
    #endif
    }
  }
}

extension PThreadIOBackend {
  /// Checks that an executor can be created with this mechanism.
  public func checkAvailability() throws {
    #if canImport(Glibc) && ExperimentalIOUring
    if self.kind == .ioUring {
      _ = try IOUringBackend()
    }
    #endif
  }
}
#endif
