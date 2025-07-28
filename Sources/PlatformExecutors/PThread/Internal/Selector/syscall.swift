//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if os(Linux) || os(Android) || os(FreeBSD) || canImport(Darwin)
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#else
#error("The IO module was unable to identify your C library.")
#endif

/// An result for an IO operation that was done on a non-blocking resource.
enum IOResult<T: Equatable>: Equatable {
  /// Signals that the IO operation could not be completed as otherwise we would need to block.
  case wouldBlock(T)

  /// Signals that the IO operation was completed.
  case processed(T)
}

extension IOResult where T: FixedWidthInteger {
  var result: T {
    switch self {
    case .processed(let value):
      return value
    case .wouldBlock(_):
      fatalError("cannot unwrap IOResult")
    }
  }
}

/// An `Error` for an IO operation.
struct IOError: Error, CustomStringConvertible {
  let description: String

  private enum Error {
    #if os(Windows)
    case windows(DWORD)
    case winsock(CInt)
    #endif
    case errno(CInt)
  }

  private let error: Error

  /// The `errno` that was set for the operation.
  var errnoCode: CInt {
    switch self.error {
    case .errno(let code):
      return code
    }
  }

  /// Creates a new `IOError``
  ///
  /// - parameters:
  ///     - errorCode: the `errno` that was set for the operation.
  ///     - reason: the actual reason (in an human-readable form).
  init(errnoCode code: CInt, reason: String) {
    self.error = .errno(code)
    self.description = reason
  }
}

@inline(__always)
@discardableResult
internal func syscall<T: FixedWidthInteger>(
  blocking: Bool,
  where function: String = #function,
  _ body: () throws -> T
) throws -> IOResult<T> {
  while true {
    let res = try body()
    if res == -1 {
      #if os(Windows)
      var err: CInt = 0
      _get_errno(&err)
      #else
      let err = errno
      #endif
      print("errno", err)
      switch (err, blocking) {
      case (EINTR, _):
        continue
      case (EWOULDBLOCK, true):
        return .wouldBlock(0)
      default:
        preconditionIsNotUnacceptableErrno(err: err, where: function)
        throw IOError(errnoCode: err, reason: function)
      }
    }
    return .processed(res)
  }
}

private func preconditionIsNotUnacceptableErrno(err: CInt, where function: String) {
  // strerror is documented to return "Unknown error: ..." for illegal value so it won't ever fail
  #if os(Windows)
  precondition(!isUnacceptableErrno(err), "unacceptable errno \(err) \(strerror(err)) in \(function))")
  #else
  precondition(
    !isUnacceptableErrno(err),
    "unacceptable errno \(err) \(String(cString: strerror(err)!)) in \(function))"
  )
  #endif
}

private func isUnacceptableErrno(_ code: Int32) -> Bool {
  // On iOS, EBADF is a possible result when a file descriptor has been reaped in the background.
  // In particular, it's possible to get EBADF from accept(), where the underlying accept() FD
  // is valid but the accepted one is not. The right solution here is to perform a check for
  // SO_ISDEFUNCT when we see this happen, but we haven't yet invested the time to do that.
  // In the meantime, we just tolerate EBADF on iOS.
  #if canImport(Darwin) && !os(macOS)
  switch code {
  case EFAULT:
    return true
  default:
    return false
  }
  #else
  switch code {
  case EFAULT, EBADF:
    return true
  default:
    return false
  }
  #endif
}
#endif
