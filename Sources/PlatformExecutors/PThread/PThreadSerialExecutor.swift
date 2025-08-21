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
/// A serial executor that provides serial execution by spawning a new thread.
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
public final class PThreadSerialExecutor: SerialExecutor, @unchecked Sendable {
  /// This is implicity unwrapped since we need to pass self as the serial executor.
  private var pThreadExecutor: PThreadExecutor!

  /// Default initializer for internal use.
  internal init() {
    // pThreadExecutor will be set by the caller
  }

  /// Creates a new `PThreadSerialExecutor` with a named background thread.
  ///
  /// This initializer creates a new executor with a dedicated background thread. The executor immediately
  /// begins processing jobs after initialization completes. The background thread continues running until
  /// the executor is deallocated.
  ///
  /// - Parameter name: The name assigned to the executor's background thread. This name appears in debugging
  ///   tools and crash reports for easier identification.
  public init(name: String) {
    self.pThreadExecutor = PThreadExecutor(
      name: name,
      serialExecutor: self.asUnownedSerialExecutor(),
      taskExecutor: nil
    )
  }

  /// Creates a new platform-native serial executor.
  ///
  /// This method creates a serial executor backed by a dedicated pthread and ensures proper
  /// thread lifecycle management. The executor's thread will be automatically stopped and
  /// joined when the body closure completes, ensuring no thread leaks.
  ///
  /// - Parameters:
  ///   - name: The name assigned to the executor's background thread.
  ///   - body: A closure that gets access to the serial executor for the duration of execution.
  /// - Returns: The value returned by the body closure.
  public nonisolated(nonsending) static func withExecutor<Return, Failure: Error>(
    name: String,
    body: (PThreadSerialExecutor) async throws(Failure) -> Return
  ) async throws(Failure) -> Return {
    do {
      return try await self._withExecutor(
        name: name,
        serialExecutor: nil,
        body: body
      )
    } catch {
      throw error as! Failure
    }
  }

  // For some reason using typed throws here trips over the compiler
  // and it is not able to reason that the thrown error inside asyncDo is a Failure
  internal nonisolated(nonsending) static func _withExecutor<Return>(
    name: String,
    serialExecutor: UnownedSerialExecutor?,
    body: (PThreadSerialExecutor) async throws -> Return
  ) async rethrows -> Return {
    let executor = PThreadSerialExecutor()
    executor.pThreadExecutor = PThreadExecutor(
      name: name,
      serialExecutor: serialExecutor ?? executor.asUnownedSerialExecutor(),
      taskExecutor: nil
    )

    return try await asyncDo {
      try await body(executor)
    } finally: {
      executor.pThreadExecutor.shutdown()
    }
  }

  public func enqueue(_ job: consuming ExecutorJob) {
    self.pThreadExecutor.enqueue(job)
  }
}

#if !canImport(Darwin)
extension PThreadSerialExecutor: SchedulingExecutor {
  public var asSchedulingExecutor: SchedulingExecutor? {
    return self
  }

  public func enqueue<C: Clock>(
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
extension PThreadSerialExecutor: CustomStringConvertible {
  public var description: String {
    "PThreadSerialExecutor(\(self.pThreadExecutor.threadDescription))"
  }
}
#endif
