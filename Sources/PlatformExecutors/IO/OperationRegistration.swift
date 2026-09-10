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
/// An opaque, stable, non-reused identity for one in-flight operation.
public struct OperationRegistration: Sendable, Hashable {
  /// The unique identifier for this registration.
  public var id: UInt

  /// Creates a new registration with the given identifier.
  ///
  /// - Parameter id: The unique identifier for this registration.
  public init(id: UInt) {
    self.id = id
  }
}
#endif
