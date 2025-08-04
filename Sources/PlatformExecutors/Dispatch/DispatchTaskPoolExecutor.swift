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
/// with the ``PlatformTaskExecutor`` for the tracking to work correctly.
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
package final class DispatchTaskPoolExecutor: TaskExecutor, @unchecked Sendable {
  private let queue: DispatchQueue
  private let taskExecutor: UnownedTaskExecutor

  package init(name: String, taskExecutor: UnownedTaskExecutor) {
    // There is no way to set the pool width of a dispatch queue
    self.queue = DispatchQueue(label: name, attributes: .concurrent)
    self.taskExecutor = taskExecutor
  }

  package func enqueue(_ job: consuming ExecutorJob) {
    let job = UnownedJob(job)
    self.queue.async {
      job.runSynchronously(on: self.taskExecutor)
    }
  }
}

#endif
