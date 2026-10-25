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

#if ExperimentalIO
/// A scheduler that can be used to perform operations.
///
/// This is the base protocol that any resource specific scheduler should inherit from. A scheduler is
/// shared by every resource that it services, so it must be `Sendable`.
///
/// A scheduler cancels an operation when the calling task is cancelled, and escalates the priority of an
/// operation when the priority of the calling task is escalated, if the platform supports it.
@available(anyAppleOS 27.0, *)
public protocol OperationScheduler: AnyObject, Sendable {
  /// Leases out an empty buffer of the scheduler.
  ///
  /// - Returns: An empty buffer.
  // TODO: Revisit if this should belong here or onto a `BufferPool` protocol.
  func leaseBuffer() -> LeasedBuffer
}
#endif
