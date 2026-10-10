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

/// Provides scoped access to an output span of the specified type and capacity across suspension points.
///
/// This is the `async` counterpart of the standard library's `withTemporaryAllocation(of:capacity:_:)`.
///
/// - Parameters:
///   - type: The type of the elements in the storage being temporarily allocated.
///   - capacity: The capacity of the output span being temporarily allocated.
///   - body: A closure to invoke and to which the allocated output span should be passed.
/// - Returns: Whatever is returned by `body`.
/// - Throws: Whatever is thrown by `body`.
@available(anyAppleOS 27.0, *)
nonisolated(nonsending) func withTemporaryAllocation<T: ~Copyable, R: ~Copyable, E: Error>(
  of type: T.Type,
  capacity: Int,
  _ body: nonisolated(nonsending) (inout OutputSpan<T>) async throws(E) -> R
) async throws(E) -> R {
  precondition(capacity >= 0, "Allocation capacity must be greater than or equal to zero")
  let (byteCount, overflow) = capacity.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
  precondition(!overflow, "Allocation byte count too large")

  // The result and the error are carried out of the allocation's scope, so
  // that the scope that holds the allocation is not generic. See
  // `withFrameAllocation(_:)` for why that matters.
  var result: Result<R, E>? = nil
  func initialize(_ pointer: UnsafeMutableRawPointer) async {
    let buffer = UnsafeMutableBufferPointer<T>(
      start: pointer.bindMemory(to: T.self, capacity: capacity),
      count: capacity
    )
    var span = OutputSpan(buffer: buffer, initializedCount: 0)
    do throws(E) {
      result = .success(try await body(&span))
    } catch {
      result = .failure(error)
    }
    let initializedCount = span.finalize(for: buffer)
    buffer.extracting(..<initializedCount).deinitialize()
  }

  // This matches the limits of the standard library's temporary allocations.
  if byteCount <= 1024 && MemoryLayout<T>.alignment <= 16 {
    await withFrameAllocation(initialize)
  } else {
    let pointer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: MemoryLayout<T>.alignment)
    await initialize(pointer)
    pointer.deallocate()
  }
  return try result.take()!.get()
}

/// Provides scoped access to 1024 bytes with an alignment of 16 in the frame of this function.
///
/// The standard library allocates temporary storage with `Builtin.stackAlloc`. In an `async` function the
/// frame lives in the task's allocator rather than on the thread's stack, so the storage outlives the
/// suspension points of `body`.
///
/// The size has to be a constant: IRGen lowers a `Builtin.stackAlloc` with a dynamic size to
/// `llvm.coro.alloca.alloc`, which the lowering of `async` functions cannot handle, while a constant size
/// becomes an ordinary `alloca` that is spilled into the frame. That is also why this function is not
/// generic, since the size would depend on a type that is only known at runtime then.
///
/// - Parameter body: A closure to invoke and to which the allocated storage should be passed.
private nonisolated(nonsending) func withFrameAllocation(
  _ body: nonisolated(nonsending) (UnsafeMutableRawPointer) async -> Void
) async {
  // The operands are literals, since IRGen has to see a constant even
  // without optimizations.
  let address = Builtin.stackAlloc(
    1024._builtinWordValue,
    1._builtinWordValue,
    16._builtinWordValue
  )
  await body(UnsafeMutableRawPointer(address))
  Builtin.stackDealloc(address)
}
#endif
