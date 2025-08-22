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

#if os(Linux) || os(FreeBSD) || canImport(Darwin)

#if canImport(Glibc)
@preconcurrency import Glibc
#elseif canImport(Musl)
@preconcurrency import Musl
#elseif canImport(Darwin)
import Darwin
#endif

enum SystemCoreCount {
  static var coreCount: Int {
    #if os(Linux)
    if let quota2 = self.coreCountCgroup2Restriction() {
      return quota2
    } else if let quota = self.coreCountCgroup1Restriction() {
      return quota
    } else if let cpusetCount = self.coreCount(cpuset: self.cpuSetPath) {
      return cpusetCount
    } else {
      return sysconf(CInt(_SC_NPROCESSORS_ONLN))
    }
    #else
    return sysconf(CInt(_SC_NPROCESSORS_ONLN))
    #endif
  }

  #if os(Linux)
  static let cfsQuotaPath = "/sys/fs/cgroup/cpu/cpu.cfs_quota_us"
  static let cfsPeriodPath = "/sys/fs/cgroup/cpu/cpu.cfs_period_us"
  static let cpuSetPath = "/sys/fs/cgroup/cpuset/cpuset.cpus"
  static let cfsCpuMaxPath = "/sys/fs/cgroup/cpu.max"

  static func coreCount(cpuset cpusetPath: String) -> Int? {
    guard
      let cpuset = try? firstLineOfFile(path: cpusetPath).split(separator: ","),
      !cpuset.isEmpty
    else { return nil }
    return cpuset.map(countCoreIds).reduce(0, +)
  }

  private static func countCoreIds(cores: Substring) -> Int {
    let ids = cores.split(separator: "-", maxSplits: 1)
    guard
      let first = ids.first.flatMap({ Int($0, radix: 10) }),
      let last = ids.last.flatMap({ Int($0, radix: 10) }),
      last >= first
    else { preconditionFailure("cpuset format is incorrect") }
    return 1 + last - first
  }

  /// Get the available core count according to cgroup1 restrictions.
  /// Round up to the next whole number.
  static func coreCountCgroup1Restriction(
    quota quotaPath: String = cfsQuotaPath,
    period periodPath: String = cfsPeriodPath
  ) -> Int? {
    guard
      let quota = try? Int(firstLineOfFile(path: quotaPath)),
      quota > 0
    else { return nil }
    guard
      let period = try? Int(firstLineOfFile(path: periodPath)),
      period > 0
    else { return nil }
    return (quota - 1 + period) / period  // always round up if fractional CPU quota requested
  }

  /// Get the available core count according to cgroup2 restrictions.
  /// Round up to the next whole number.
  static func coreCountCgroup2Restriction(cpuMaxPath: String = cfsCpuMaxPath) -> Int? {
    guard let maxDetails = try? firstLineOfFile(path: cpuMaxPath),
      let spaceIndex = maxDetails.firstIndex(of: " "),
      let quota = Int(maxDetails[maxDetails.startIndex..<spaceIndex]),
      let period = Int(maxDetails[maxDetails.index(after: spaceIndex)..<maxDetails.endIndex])
    else { return nil }
    return (quota - 1 + period) / period  // always round up if fractional CPU quota requested
  }

  private static func firstLineOfFile(path: String) throws -> String {
    let fd = try retryingSyscall(blocking: false) {
      open(path, O_RDONLY)
    }.result
    guard fd != -1 else {
      throw SystemError()
    }

    let result = Result {
      var buffer = [UInt8](repeating: 0, count: 4096)
      let bytesRead = try retryingSyscall(blocking: false) {
        read(fd, &buffer, buffer.count)
      }.result
      guard bytesRead > 0 else {
        throw SystemError()
      }

      let content = String(decoding: buffer[0..<Int(bytesRead)], as: UTF8.self)
      return trim(content)
    }

    try retryingSyscall(blocking: false) {
      close(fd)
    }

    return try result.get()
  }

  private static func trim(_ s: String) -> String {
    guard let first = s.firstIndex(where: { !$0.isWhitespace && !$0.isNewline }) else {
      return String()
    }
    let last = s.lastIndex(where: { !$0.isWhitespace && !$0.isNewline })!
    return String(s[first...last])
  }

  private struct SystemError: Error {}

  #endif
}

#endif
