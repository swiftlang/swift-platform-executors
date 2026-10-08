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

/// Submits one operation to the scheduler and awaits its result.
///
/// - Parameters:
///   - scheduler: The scheduler to submit the operation to.
///   - isCancellable: Whether cancelling the current task cancels the operation. Operations that release a
///     resource must not be cancelled, since the resource would leak otherwise.
///   - submit: Submits the operation with the given continuation and per-operation state.
/// - Returns: The result of the operation.
// TODO: Adopt the split continuation once it is available.
@available(anyAppleOS 27.0, *)
nonisolated(nonsending) func withOperation<Scheduler: OperationScheduler, Success: ~Copyable>(
  on scheduler: Scheduler,
  of: Success.Type = Success.self,
  _ submit: (consuming Continuation<Success, IOError>, inout OutputSpan<Scheduler.OperationState>) ->
    OperationRegistration
) async throws(IOError) -> Success {
  // TODO: This can be done safely with async entrypoints
  let buffer = UnsafeMutableBufferPointer<Scheduler.OperationState>.allocate(capacity: 1)
  var initializedCount = 0
  defer {
    buffer.extracting(..<initializedCount).deinitialize()
    buffer.deallocate()
  }

  // TODO: We need to support cancellation when we have the split continuation
  return try await withContinuation(of: Success.self, throwing: IOError.self) { continuation in
    var state = OutputSpan(buffer: buffer, initializedCount: 0)
    _ = submit(continuation, &state)
    initializedCount = state.finalize(for: buffer)
  }
}
#endif
