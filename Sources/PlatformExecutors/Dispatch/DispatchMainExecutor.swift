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

@available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
package class DispatchMainExecutor: MainExecutor, @unchecked Sendable {
  var threaded = false

  package init() {}

  package func run() throws {
    if self.threaded {
      fatalError("DispatchMainExecutor does not support recursion")
    }

    self.threaded = true
    _dispatchMain()
  }

  package func stop() {
    fatalError("DispatchMainExecutor cannot be stopped")
  }

  package func enqueue(_ job: consuming ExecutorJob) {
    _dispatchEnqueueMain(
      _Concurrency.UnownedJob(job),
      serialExecutor: self.asUnownedSerialExecutor()
    )
  }

  package func checkIsolated() {
    _dispatchAssertMainQueue()
  }
}

#endif
