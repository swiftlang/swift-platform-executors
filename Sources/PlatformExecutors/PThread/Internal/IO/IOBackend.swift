//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if os(Linux) || os(Android) || os(FreeBSD) || canImport(Darwin) || os(WASI)
/// The mechanism that a ``PThreadExecutor`` performs its I/O with.
///
/// This connects the executor with the underlying platform. It allows the platform to use readiness or
/// completion based primitives.
///
/// ## Threading
///
/// ``wakeup(_:)`` can be called from any thread. Everything else is only ever called on the executor's thread.
///
/// - Note: Nothing is ever dispatched through this protocol. The executor will call directly to a backend.
/// The purpose of this protocol is to ensure that all backends provide the same uniform API
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
protocol IOBackend: ~Copyable {
  /// The handle that other threads use to wake this backend up.
  associatedtype WakeupHandle: Sendable

  /// The handle that other threads use to wake this backend up.
  var wakeupHandle: WakeupHandle { get }

  /// Creates a new backend.
  init() throws

  /// Wakes up a backend that is waiting for work.
  ///
  /// - Note: This can be called from any thread.
  ///
  /// - Parameter handle: The handle of the backend to wake up.
  static func wakeup(_ handle: WakeupHandle) throws

  /// Waits for work to become available.
  ///
  /// - Parameter strategy: How long to wait for work to become available.
  mutating func wait(strategy: IOWaitStrategy) throws
}
#endif
