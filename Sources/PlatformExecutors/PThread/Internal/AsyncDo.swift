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

/// Structured resource management helper that ensures cleanup code runs in all execution paths.
///
/// This function guarantees that the finally block will execute even if the body throws an error
/// or the task is cancelled. The finally block runs in an uncancellable task to prevent resource leaks.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
nonisolated(nonsending) func asyncDo<Return, Failure: Error>(
  body: () async throws(Failure) -> Return,
  finally: sending @escaping () async -> Void
) async throws(Failure) -> Return {
  let result: Return
  do {
    result = try await body()
  } catch {
    await Task {
      await finally()
    }.value
    throw error
  }

  await Task {
    await finally()
  }.value
  return result
}
