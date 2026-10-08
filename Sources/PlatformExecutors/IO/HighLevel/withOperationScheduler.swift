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
/// Prefers the given operation scheduler for the resources created in the given operation.
///
/// Resources resolve the operation scheduler that services them once when they are created and keep using
/// it for all of their operations. The resolution walks these places in order and takes the first operation
/// scheduler that services the resource:
///
/// 1. The operation schedulers pushed with this method, from the innermost scope outward.
/// 2. The task executor preference of the current task, if the task executor is an operation scheduler.
///
/// Nested calls push onto each other, so a resource that the innermost operation scheduler cannot service
/// falls back to the outer ones:
///
/// ```swift
/// try await withOperationScheduler(ioUringScheduler) {
///   try await withOperationScheduler(epollScheduler) {
///     // TCP sockets created here use epoll if it services them,
///     // and io_uring otherwise.
///     var connection = try await TCPConnection.connect(to: address)
///     ...
///   }
/// }
/// ```
///
/// - Parameters:
///   - scheduler: The operation scheduler to prefer.
///   - operation: The operation to run with the preference.
/// - Returns: The value that the operation returned.
// TODO: Fall back to a default operation scheduler once we have one.
@available(anyAppleOS 27.0, *)
public nonisolated(nonsending) func withOperationScheduler<Return, Failure: Error>(
  _ scheduler: some OperationScheduler,
  operation: nonisolated(nonsending) () async throws(Failure) -> Return
) async throws(Failure) -> Return {
  let preference = OperationSchedulerPreference(
    scheduler: scheduler,
    outer: OperationSchedulerPreference.innermost
  )

  // Task locals rethrow untyped errors.
  let result = await OperationSchedulerPreference.$innermost.withValue(preference) {
    () async -> Result<Return, Failure> in
    do throws(Failure) {
      return .success(try await operation())
    } catch {
      return .failure(error)
    }
  }
  return try result.get()
}

/// An operation scheduler pushed with ``withOperationScheduler(_:operation:)``.
// TODO: We should find a better way than a class for this.
@available(anyAppleOS 27.0, *)
final class OperationSchedulerPreference: Sendable {
  /// The innermost preference of the current task.
  @TaskLocal
  static var innermost: OperationSchedulerPreference?

  /// The preferred operation scheduler.
  let scheduler: any OperationScheduler

  /// The preference of the enclosing scope.
  let outer: OperationSchedulerPreference?

  init(scheduler: any OperationScheduler, outer: OperationSchedulerPreference?) {
    self.scheduler = scheduler
    self.outer = outer
  }

  /// Resolves the operation scheduler for a resource of the current task.
  ///
  /// - Parameter schedulerType: The type of operation scheduler that services the resource. This is usually
  ///   the existential of a resource specific protocol, such as `(any TCPSocketOperationScheduler).self`.
  ///   Existentials do not conform to their own protocol, so the type is not constrained to
  ///   ``OperationScheduler``.
  /// - Returns: The resolved operation scheduler, or `nil` if no operation scheduler services the resource.
  static func resolve<Scheduler>(
    as schedulerType: Scheduler.Type
  ) -> Scheduler? {
    var preference = Self.innermost
    while let current = preference {
      if let scheduler = current.scheduler as? Scheduler {
        return scheduler
      }
      preference = current.outer
    }

    let taskExecutor = withUnsafeCurrentTask { $0?.unownedTaskExecutor }?.asTaskExecutor()
    if let scheduler = taskExecutor as? Scheduler {
      return scheduler
    }
    return nil
  }
}
#endif
