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

#if compiler(<6.4)
/// Backfills `withTemporaryAllocation(of:capacity:_:)` for compilers before Swift 6.4.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
func withTemporaryAllocation<T: ~Copyable, R: ~Copyable, E: Error>(
  of type: T.Type,
  capacity: Int,
  _ body: (inout OutputSpan<T>) throws(E) -> R
) throws(E) -> R {
  try withUnsafeTemporaryAllocation(of: type, capacity: capacity) { (buffer) throws(E) in
    var span = OutputSpan(buffer: buffer, initializedCount: 0)
    defer {
      let initializedCount = span.finalize(for: buffer)
      span = OutputSpan()
      buffer.extracting(..<initializedCount).deinitialize()
    }

    return try body(&span)
  }
}
#endif
