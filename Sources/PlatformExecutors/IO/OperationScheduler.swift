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
/// This is the base protocol that any resource specific scheduler should inherit from.
public protocol OperationScheduler: AnyObject {
  /// Per-operation state passed to the resource specific submit methods.
  associatedtype OperationState: ~Copyable

  /// Performs the given operation.
  ///
  /// - Parameter registration: The registration of the operation.
  func cancel(
    _ registration: OperationRegistration
  )

  /// Performs the given operation.
  ///
  /// - Parameters:
  ///   - registration: The registration of the operation.
  ///   - newPriority: The new priority to set.
  func escalatePriority(
    of registration: OperationRegistration,
    to newPriority: TaskPriority
  )
}
#endif
