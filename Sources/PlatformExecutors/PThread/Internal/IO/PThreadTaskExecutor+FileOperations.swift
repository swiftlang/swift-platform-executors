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
@_spi(SplitContinuation) import _Concurrency

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

// MARK: - File operations

/// A pool performs file operations with blocking syscalls on a separate pool of threads.
@available(anyAppleOS 27.0, *)
extension PThreadTaskExecutor: FileOperationScheduler {
  public typealias FileHandle = PThreadFile

  public func open(
    path: String,
    configuration: FileOpenConfiguration
  ) async throws(IOError) -> FileHandle {
    try await FileSyscall.withCPath(path) { path async throws(IOError) -> FileHandle in
      let fileDescriptor = try await self.performBlocking(
        .openFile(
          path: path,
          flags: FileSyscall.flags(for: configuration),
          permissions: FileSyscall.permissions(for: configuration)
        )
      )
      return PThreadFile(fileDescriptor: CInt(fileDescriptor), executorIndex: 0)
    }
  }

  public func read(
    file: borrowing FileHandle,
    into buffer: inout OutputRawSpan,
    at offset: Int64
  ) async throws(IOError) -> Int {
    // The bytes are read into the free capacity of the buffer.
    let freeCapacity = buffer.withUnsafeMutableBytes { bytes, initializedCount in
      UnsafeMutableRawBufferPointer(rebasing: bytes[initializedCount...])
    }
    let count = try await self.performBlocking(
      .readFile(file: file.fileDescriptor, buffer: freeCapacity, offset: offset)
    )
    buffer.withUnsafeMutableBytes { _, initializedCount in
      initializedCount += count
    }
    return count
  }

  public func write(
    file: borrowing FileHandle,
    from buffer: RawSpan,
    at offset: Int64
  ) async throws(IOError) -> Int {
    let bytes = buffer.withUnsafeBytes { $0 }
    return try await self.performBlocking(
      .writeFile(file: file.fileDescriptor, buffer: bytes, offset: offset)
    )
  }

  public func close(file: consuming FileHandle) async throws(IOError) {
    _ = try await self.performBlocking(.close(fileDescriptor: file.fileDescriptor))
  }

  /// Performs the operation with a blocking syscall on one of the threads for blocking work.
  ///
  /// - Parameter operation: The operation to perform.
  /// - Returns: The result of the operation.
  private func performBlocking(_ operation: IOOperation) async throws(IOError) -> Int {
    let queue = self.blockingQueue()
    return try await withContinuation(of: Int.self, throwing: IOError.self) {
      (continuation, awaiter) async throws(IOError) -> Int in
      let id = queue.submit(
        operation: operation,
        priority: Task.currentPriority,
        continuation: continuation
      )
      return try await awaiter.wait(
        onCancel: { queue.cancel(id) },
        onEscalate: { newPriority in queue.escalate(id, to: newPriority) }
      )
    }
  }
}
#endif
#endif
