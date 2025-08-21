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
/// A main executor that provides serial execution by taking over the current thread.
///
/// ## Usage
///
/// ```swift
/// // Create main executor on current thread
/// let mainExecutor = PThreadMainExecutor()
///
/// // Run the executor loop
/// try mainExecutor.run()
///
/// // Stop the executor from another context
/// mainExecutor.stop()
/// ```
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
package final class PThreadMainExecutor: SerialExecutor, @unchecked Sendable {
  private let pThreadExecutor: PThreadExecutor!

  /// Creates a new `PThreadMainExecutor` that takes control of the current thread.
  package init() {
    self.pThreadExecutor = PThreadExecutor()
  }

  package func enqueue(_ job: UnownedJob) {
    self.pThreadExecutor.enqueue(job)
  }

  package func run() throws {
    // We are taking over the current thread
    try self.pThreadExecutor.run { job in
      job.runSynchronously(on: self.asUnownedSerialExecutor())
    }
  }

  package func stop() {
    // We are not waiting on the condition variable since it would result in a
    // dead lock due to us taking over the thread previously.
    _ = self.pThreadExecutor.stop()
  }
}

#if !canImport(Darwin)
extension PThreadMainExecutor: MainExecutor {}
extension PThreadMainExecutor: SchedulingExecutor {
  package var asSchedulingExecutor: SchedulingExecutor? {
    return self
  }

  package func enqueue<C: Clock>(
    _ job: consuming ExecutorJob,
    at instant: C.Instant,
    tolerance: C.Duration?,
    clock: C
  ) {
    self.pThreadExecutor.enqueue(job, at: instant, tolerance: tolerance, clock: clock)
  }
}
#endif

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension PThreadMainExecutor: CustomStringConvertible {
  package var description: String {
    "PThreadMainExecutor(\(self.pThreadExecutor.threadDescription))"
  }
}
#endif
