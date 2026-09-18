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
//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2024 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if canImport(Glibc)
import Glibc
import CPlatformExecutors

internal enum TimerFileDescriptor {
  internal static let TFD_CLOEXEC = CPlatformExecutors.TFD_CLOEXEC
  internal static let TFD_NONBLOCK = CPlatformExecutors.TFD_NONBLOCK

  internal static func timerfd_settime(
    fd: CInt,
    flags: CInt,
    newValue: UnsafePointer<itimerspec>,
    oldValue: UnsafeMutablePointer<itimerspec>?
  ) throws {
    _ = try retryingSyscall(blocking: false) {
      CPlatformExecutors.timerfd_settime(fd, flags, newValue, oldValue)
    }
  }

  internal static func timerfd_create(clockId: CInt, flags: CInt) throws -> CInt {
    try retryingSyscall(blocking: false) {
      CPlatformExecutors.timerfd_create(clockId, flags)
    }.result
  }
  internal static func timerfd_read(
    descriptor: CInt,
    pointer: UnsafeMutableRawPointer,
    size: size_t
  ) throws -> IOResult<ssize_t> {
    try syscallForbiddingEINVAL {
      read(descriptor, pointer, size)
    }
  }
}

#endif
