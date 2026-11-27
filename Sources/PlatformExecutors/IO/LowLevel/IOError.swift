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
/// An error thrown by an I/O operation.
///
/// - Note: This is a placeholder for the portable error currency type and only carries the platform's
/// error code right now.
@available(SwiftPlatformExecutors 0.1.0, *)
public struct IOError: Error, Hashable, Sendable {
  /// The code identifying why an operation failed.
  public struct Code: Hashable, Sendable {
    fileprivate enum Backing: Hashable, Sendable {
      case cancelled
      case writeZero
      case platform(CInt)
    }

    fileprivate var backing: Backing

    /// The operation was cancelled before it completed.
    public static var cancelled: Code { Code(backing: .cancelled) }

    /// A write transferred no bytes of a buffer that isn't empty.
    ///
    /// The loops that write all bytes of a buffer rely on every write making progress, so a scheduler throws this
    /// instead of returning zero.
    public static var writeZero: Code { Code(backing: .writeZero) }

    /// The operation failed with the given platform specific error code.
    ///
    /// On POSIX-like platforms this is an `errno` value.
    ///
    /// - Parameter code: The platform specific error code.
    /// - Returns: A code wrapping the platform specific error code.
    public static func platform(_ code: CInt) -> Code { Code(backing: .platform(code)) }

    /// The platform specific error code, if this code wraps one.
    public var platformCode: CInt? {
      switch self.backing {
      case .cancelled, .writeZero: nil
      case .platform(let code): code
      }
    }
  }

  /// The code identifying why the operation failed.
  public var code: Code

  /// Creates a new error with the given code.
  ///
  /// - Parameter code: The code identifying why the operation failed.
  public init(code: Code) {
    self.code = code
  }
}
#endif
