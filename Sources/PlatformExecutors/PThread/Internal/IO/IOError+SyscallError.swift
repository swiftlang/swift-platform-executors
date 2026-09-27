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

extension IOError {
  /// Creates an error from a failed syscall.
  ///
  /// - Parameter error: The error of the failed syscall.
  init(_ error: SyscallError) {
    self.init(code: .platform(error.errnoCode))
  }

  /// Creates an error from an `errno`.
  ///
  /// - Parameter errnoCode: The `errno` that was set for the operation.
  init(errnoCode: CInt) {
    self.init(code: .platform(errnoCode))
  }
}

/// Performs a syscall, retrying it while it is interrupted, and reports a failure as an ``IOError``.
@inline(__always)
@discardableResult
func retryingIOSyscall<T: FixedWidthInteger>(
  blocking: Bool,
  where function: String = #function,
  _ body: () -> T
) throws(IOError) -> IOResult<T> {
  do {
    return try retryingSyscall(blocking: blocking, where: function, body)
  } catch {
    throw IOError(error)
  }
}
#endif
#endif
