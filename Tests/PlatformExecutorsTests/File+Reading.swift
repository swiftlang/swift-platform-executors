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
#if os(Linux) || os(FreeBSD) || canImport(Darwin)

@_spi(ExperimentalScheduling) @_spi(ConcurrencyExecutors) @_spi(ExperimentalCustomExecutors) import PlatformExecutors
import BasicContainers

// TODO: Replace with AsyncStreaming interfaces
@available(anyAppleOS 27.0, *)
extension File {
  /// Reads at most `length` bytes from the given offset.
  borrowing func read(length: Int, at offset: Int64) async throws(IOError) -> [UInt8] {
    var bytes = UniqueArray<UInt8>(minimumCapacity: length)
    _ = try await bytes.append(addingByteCount: length) { (output: inout OutputRawSpan) async throws(IOError) -> Int in
      try await self.read(into: &output, at: offset)
    }
    return bytes.copyToArray()
  }

  /// Reads from the start of the file until its end.
  borrowing func readAll() async throws(IOError) -> [UInt8] {
    var contents = UniqueArray<UInt8>()
    while true {
      let offset = Int64(contents.count)
      let count = try await contents.append(addingByteCount: 64 * 1024) {
        (output: inout OutputRawSpan) async throws(IOError) -> Int in
        try await self.read(into: &output, at: offset)
      }
      if count == 0 {
        return contents.copyToArray()
      }
    }
  }
}

@available(anyAppleOS 27.0, *)
extension File.Readable {
  /// Reads at most `length` bytes from the given offset.
  borrowing func read(length: Int, at offset: Int64) async throws(IOError) -> [UInt8] {
    var bytes = UniqueArray<UInt8>(minimumCapacity: length)
    _ = try await bytes.append(addingByteCount: length) { (output: inout OutputRawSpan) async throws(IOError) -> Int in
      try await self.read(into: &output, at: offset)
    }
    return bytes.copyToArray()
  }

  /// Reads from the start of the file until its end.
  borrowing func readAll() async throws(IOError) -> [UInt8] {
    var contents = UniqueArray<UInt8>()
    while true {
      let offset = Int64(contents.count)
      let count = try await contents.append(addingByteCount: 64 * 1024) {
        (output: inout OutputRawSpan) async throws(IOError) -> Int in
        try await self.read(into: &output, at: offset)
      }
      if count == 0 {
        return contents.copyToArray()
      }
    }
  }
}

extension UniqueArray<UInt8> {
  /// Copies the bytes into an array.
  borrowing func copyToArray() -> [UInt8] {
    self.span.withUnsafeBufferPointer { Array($0) }
  }
}

#endif
#endif
