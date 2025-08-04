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

#if canImport(Darwin)
import Dispatch

/// This wrapper primarly exists since we need to call the `runSynchronously`
/// with the ``PlatformSerialExecutor`` for the tracking to work correctly.
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
package final class DispatchSerialExecutor: SerialExecutor, @unchecked Sendable {
  private let queue: DispatchQueue
  private let serialExecutor: UnownedSerialExecutor

  package init(name: String, serialExecutor: UnownedSerialExecutor) {
    self.queue = DispatchQueue(label: name)
    self.serialExecutor = serialExecutor
  }

  package func enqueue(_ job: consuming ExecutorJob) {
    let job = UnownedJob(job)
    self.queue.async {
      job.runSynchronously(on: self.serialExecutor)
    }
  }
}

#endif
