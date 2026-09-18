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

#if !os(Windows)
import CPlatformExecutors

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension timespec {
  init(duration: Duration) {
    let nsecPerSec: Int64 = 1_000_000_000
    let attosecondsPerNanosecond: Int64 = 1_000_000_000

    // Convert attoseconds to nanoseconds
    let totalNanoseconds = duration.components.attoseconds / attosecondsPerNanosecond

    // Extract seconds and remaining nanoseconds
    let seconds = totalNanoseconds / nsecPerSec
    let nanoseconds = totalNanoseconds % nsecPerSec

    self = timespec(
      tv_sec: time_t(duration.components.seconds + seconds),
      tv_nsec: Int(nanoseconds)
    )
  }
}
#endif
