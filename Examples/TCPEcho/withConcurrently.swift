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

#if ExperimentalIO && (os(Linux) || os(FreeBSD) || canImport(Darwin))
/// Runs both closures concurrently in child tasks and returns once both returned.
///
/// This is only needed since task groups don't support `~Escapable` type capturing right now
// TODO: Remove _semantics once https://github.com/swiftlang/swift/issues/93106 is fixed
@_semantics("optimize.sil.specialize.generic.never")
@available(anyAppleOS 27.0, *)
nonisolated(nonsending) func withConcurrently<First: Sendable, Second: Sendable, Failure: Error>(
  _ first: @Sendable () async throws(Failure) -> First,
  _ second: @Sendable () async throws(Failure) -> Second
) async throws(Failure) -> (First, Second) {
  // The closures only escape into child tasks that finish before we return,
  // so they do not actually escape.
  try await withoutActuallyEscaping(first) { (first) async throws(Failure) -> (First, Second) in
    try await withoutActuallyEscaping(second) { (second) async throws(Failure) -> (First, Second) in
      var first = Optional(first)
      var second = Optional(second)
      return try await _withConcurrently(&first, &second)
    }
  }
}

@available(anyAppleOS 27.0, *)
private nonisolated(nonsending) func _withConcurrently<First: Sendable, Second: Sendable, Failure: Error>(
  _ first: inout (@Sendable () async throws(Failure) -> First)?,
  _ second: inout (@Sendable () async throws(Failure) -> Second)?
) async throws(Failure) -> (First, Second) {
  let first = first.take()!
  let second = second.take()!

  // Task groups do not support typed errors, so the result is carried through a `Result`.
  let result = await withTaskGroup(
    of: ConcurrentResult<First, Second, Failure>.self
  ) { group -> Result<(First, Second), Failure> in
    group.addTask {
      do throws(Failure) {
        return .first(try await first())
      } catch {
        return .failure(error)
      }
    }
    group.addTask {
      do throws(Failure) {
        return .second(try await second())
      } catch {
        return .failure(error)
      }
    }

    var firstValue: First? = nil
    var secondValue: Second? = nil
    var failure: Failure? = nil
    while let result = await group.next() {
      switch result {
      case .first(let value):
        firstValue = value
      case .second(let value):
        secondValue = value
      case .failure(let error):
        if failure == nil {
          failure = error
          group.cancelAll()
        }
      }
    }

    if let failure {
      return .failure(failure)
    }
    return .success((firstValue!, secondValue!))
  }
  return try result.get()
}

/// The result of one of the child tasks of ``withConcurrently(_:_:)``.
private enum ConcurrentResult<First: Sendable, Second: Sendable, Failure: Error>: Sendable {
  case first(First)
  case second(Second)
  case failure(Failure)
}
#endif
