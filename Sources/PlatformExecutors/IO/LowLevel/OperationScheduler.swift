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
@available(anyAppleOS 27.0, *)
public protocol OperationScheduler: AnyObject, Sendable {}
#endif
