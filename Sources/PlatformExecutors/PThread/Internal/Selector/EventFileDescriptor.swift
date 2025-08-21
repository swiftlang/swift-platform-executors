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

enum EventFileDescriptor {
  static let EFD_CLOEXEC = CPlatformExecutors.EFD_CLOEXEC
  static let EFD_NONBLOCK = CPlatformExecutors.EFD_NONBLOCK
  typealias eventfd_t = CPlatformExecutors.eventfd_t

  @inline(never)
  static func eventfd_read(fd: CInt, value: UnsafeMutablePointer<UInt64>) throws -> CInt {
    return try retryingSyscall(blocking: false) {
      CPlatformExecutors.eventfd_read(fd, value)
    }.result
  }

  @inline(never)
  internal static func eventfd_write(fd: CInt, value: UInt64) throws -> CInt {
    return try retryingSyscall(blocking: false) {
      CPlatformExecutors.eventfd_write(fd, value)
    }.result
  }

  @inline(never)
  static func makeEventFileDescriptor(initval: CUnsignedInt, flags: CInt) throws -> CInt {
    return try retryingSyscall(blocking: false) {
      // Note: Please do _not_ remove the `numericCast`, this is to allow compilation in Ubuntu 14.04 and
      // other Linux distros which ship a glibc from before this commit:
      // https://sourceware.org/git/?p=glibc.git;a=commitdiff;h=69eb9a183c19e8739065e430758e4d3a2c5e4f1a
      // which changes the first argument from `CInt` to `CUnsignedInt` (from Sat, 20 Sep 2014).
      CPlatformExecutors.eventfd(numericCast(initval), flags)
    }.result
  }
}
#endif
