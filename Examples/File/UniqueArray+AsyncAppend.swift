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
import BasicContainers

// TODO: Should be removed once we get stdlib APIs that offer `OutputSpan` in async contexts.
@available(anyAppleOS 27.0, *)
extension UniqueArray where Element: ~Copyable {
  /// Appends the elements that a closure initializes in an output span, which it can do across suspension
  /// points.
  ///
  /// - Parameters:
  ///   - newItemCount: The maximum number of elements to append.
  ///   - initializer: A closure that initializes up to `newItemCount` elements in the output span.
  /// - Returns: Whatever `initializer` returns.
  /// - Throws: Whatever `initializer` throws.
  mutating func append<E: Error, R: ~Copyable>(
    addingCount newItemCount: Int,
    initializingWith initializer: (inout OutputSpan<Element>) async throws(E) -> R
  ) async throws(E) -> R {
    let freeCapacity = unsafe self.reserveFreeCapacity(newItemCount)
    var span = unsafe OutputSpan(buffer: freeCapacity, initializedCount: 0)
    defer {
      unsafe self.addInitializedCount(span.finalize(for: freeCapacity))
      span = OutputSpan()
    }
    return try await initializer(&span)
  }

  private mutating func reserveFreeCapacity(_ newItemCount: Int) -> UnsafeMutableBufferPointer<Element> {
    precondition(newItemCount >= 0, "Cannot add a negative number of items")
    self.reserveCapacity(self.count + newItemCount)
    return unsafe self.edit { span in
      unsafe span.withUnsafeMutableBufferPointer { buffer, initializedCount in
        buffer.extracting(initializedCount..<initializedCount + newItemCount)
      }
    }
  }

  private mutating func addInitializedCount(_ initializedCount: Int) {
    self.edit { span in
      unsafe span.withUnsafeMutableBufferPointer { _, count in
        count += initializedCount
      }
    }
  }
}

@available(anyAppleOS 27.0, *)
extension UniqueArray<UInt8> {
  /// Appends the bytes that a closure initializes in an output raw span, which it can do across suspension
  /// points.
  ///
  /// - Parameters:
  ///   - newByteCount: The maximum number of bytes to append.
  ///   - initializer: A closure that initializes up to `newByteCount` bytes in the output raw span.
  /// - Returns: Whatever `initializer` returns.
  /// - Throws: Whatever `initializer` throws.
  mutating func append<E: Error, R: ~Copyable>(
    addingByteCount newByteCount: Int,
    initializingWith initializer: (inout OutputRawSpan) async throws(E) -> R
  ) async throws(E) -> R {
    try await self.append(addingCount: newByteCount) { (span: inout OutputSpan<UInt8>) async throws(E) -> R in
      let buffer = unsafe span.withUnsafeMutableBufferPointer { buffer, _ in UnsafeMutableRawBufferPointer(buffer) }
      var bytes = unsafe OutputRawSpan(buffer: buffer, initializedCount: 0)
      defer {
        let byteCount = unsafe bytes.finalize(for: buffer)
        bytes = OutputRawSpan()
        unsafe span.withUnsafeMutableBufferPointer { _, initializedCount in
          initializedCount = byteCount
        }
      }
      return try await initializer(&bytes)
    }
  }
}
#endif
