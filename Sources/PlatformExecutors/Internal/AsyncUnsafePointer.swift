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
import Builtin

/// Calls the body with a pointer to the value, and the pointer stays valid across suspension points of the body.
///
/// This is the `async` counterpart of the standard library's `withUnsafeMutablePointer(to:_:)`.
///
/// - Parameters:
///   - value: The value to point at.
///   - body: A closure to invoke and to which the pointer should be passed.
/// - Returns: Whatever is returned by `body`.
/// - Throws: Whatever is thrown by `body`.
@available(anyAppleOS 27.0, *)
nonisolated(nonsending) func withUnsafeMutablePointer<T: ~Copyable, R: ~Copyable, E: Error>(
  to value: inout T,
  _ body: nonisolated(nonsending) (UnsafeMutablePointer<T>) async throws(E) -> R
) async throws(E) -> R {
  let address = Int(Builtin.ptrtoint_Word(Builtin.addressof(&value)))
  return try await unsafe body(UnsafeMutablePointer<T>(bitPattern: address).unsafelyUnwrapped)
}
#endif
