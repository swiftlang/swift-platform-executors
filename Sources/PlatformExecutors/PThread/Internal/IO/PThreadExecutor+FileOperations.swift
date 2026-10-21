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
#if os(Linux) || os(Android) || os(FreeBSD) || canImport(Darwin)
@_spi(ExperimentalScheduling) @_spi(ConcurrencyExecutors) @_spi(ExperimentalCustomExecutors) import _Concurrency

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

// MARK: - File operations

/// The file operations that the executor's mechanism performs.
@available(anyAppleOS 27.0, *)
extension PThreadExecutor {
  package func openFile(
    path: String,
    configuration: FileOpenConfiguration
  ) async throws(IOError) -> PThreadFile {
    try await unsafe FileSyscall.withCPath(path) { path async throws(IOError) -> PThreadFile in
      let operation = unsafe IOOperation.openFile(
        path: path,
        flags: FileSyscall.flags(for: configuration),
        permissions: FileSyscall.permissions(for: configuration)
      )
      let fileDescriptor = try await unsafe self.perform(operation) { continuation in
        .byteCount(continuation)
      }
      return PThreadFile(fileDescriptor: CInt(fileDescriptor))
    }
  }

  package func readFile(
    _ file: borrowing PThreadFile,
    into buffer: inout OutputRawSpan,
    at offset: Int64
  ) async throws(IOError) -> Int {
    let freeCapacity = unsafe buffer.withUnsafeMutableBytes { bytes, initializedCount in
      unsafe UnsafeMutableRawBufferPointer(rebasing: bytes[initializedCount...])
    }

    let count = try await unsafe self.perform(
      .readFile(file: file.fileDescriptor, buffer: freeCapacity, offset: offset)
    ) { continuation in
      .byteCount(continuation)
    }

    // The kernel wrote into the free capacity of the buffer so we have to
    // update the initialized count now.
    unsafe buffer.withUnsafeMutableBytes { _, initializedCount in
      initializedCount += count
    }
    return count
  }

  package func writeFile(
    _ file: borrowing PThreadFile,
    from buffer: RawSpan,
    at offset: Int64
  ) async throws(IOError) -> Int {
    let bytes = buffer.withUnsafeBytes { unsafe $0 }
    return try await unsafe self.perform(
      .writeFile(file: file.fileDescriptor, buffer: bytes, offset: offset)
    ) { continuation in
      .byteCount(continuation)
    }
  }

  package func closeFile(_ file: consuming PThreadFile) async throws(IOError) {
    try await unsafe self.perform(.close(fileDescriptor: file.fileDescriptor)) { continuation in
      .void(continuation)
    }
  }
}
#endif
#endif
