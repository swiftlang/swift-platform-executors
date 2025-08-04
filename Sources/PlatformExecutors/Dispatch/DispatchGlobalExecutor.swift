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

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
package final class DispatchGlobalTaskExecutor: TaskExecutor, @unchecked Sendable {
  package init() {}

  package func enqueue(_ job: consuming ExecutorJob) {
    _dispatchEnqueueGlobal(
      _Concurrency.UnownedJob(job),
      taskExecutor: self.asUnownedTaskExecutor()
    )
  }
}

#endif
