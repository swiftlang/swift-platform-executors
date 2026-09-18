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

/// How long an I/O mechanism waits for work to become available.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
enum IOWaitStrategy {
  /// Block until there is some I/O ready to be processed or the mechanism is explicitly woken up.
  case block

  /// Block until one of the clocks is ready
  case blockUntilTimeout(
    continuousClockInstant: ContinuousClock.Instant?,
    suspendingClockInstant: SuspendingClock.Instant?
  )

  /// Take all the I/O that is ready at this point in time without blocking at all.
  case now
}
