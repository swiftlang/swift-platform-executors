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

/// Depending on the backend either the backend performs the file operations or we fallback to a pool of threads.
@available(anyAppleOS 27.0, *)
extension PThreadTaskExecutor: FileOperationScheduler {
  public typealias FileHandle = PThreadFile

  public func open(
    path: String,
    configuration: FileOpenConfiguration
  ) async throws(IOError) -> FileHandle {
    if self.performsFileOperations {
      return try await self.next().openFile(path: path, configuration: configuration)
    }

    return try await unsafe FileSyscall.withCPath(path) { path async throws(IOError) -> FileHandle in
      let fileDescriptor = try await unsafe self.performBlocking(
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
    if self.performsFileOperations {
      return try await unsafe self.executors[file.executorIndex].readFile(file, into: &buffer, at: offset)
    }

    // The bytes are read into the free capacity of the buffer.
    let freeCapacity = unsafe buffer.withUnsafeMutableBytes { bytes, initializedCount in
      unsafe UnsafeMutableRawBufferPointer(rebasing: bytes[initializedCount...])
    }
    let count = try await unsafe self.performBlocking(
      .readFile(file: file.fileDescriptor, buffer: freeCapacity, offset: offset)
    )
    unsafe buffer.withUnsafeMutableBytes { _, initializedCount in
      initializedCount += count
    }
    return count
  }

  public func write(
    file: borrowing FileHandle,
    from buffer: RawSpan,
    at offset: Int64
  ) async throws(IOError) -> Int {
    if self.performsFileOperations {
      return try await unsafe self.executors[file.executorIndex].writeFile(file, from: buffer, at: offset)
    }

    let bytes = buffer.withUnsafeBytes { unsafe $0 }
    return try await unsafe self.performBlocking(
      .writeFile(file: file.fileDescriptor, buffer: bytes, offset: offset)
    )
  }

  public func close(file: consuming FileHandle) async throws(IOError) {
    if self.performsFileOperations {
      return try await unsafe self.executors[file.executorIndex].closeFile(file)
    }
    _ = try await unsafe self.performBlocking(.close(fileDescriptor: file.fileDescriptor))
  }

  /// Performs the operation with a blocking syscall on one of the threads for blocking work.
  ///
  /// - Parameter operation: The operation to perform.
  /// - Returns: The result of the operation.
  private func performBlocking(_ operation: IOOperation) async throws(IOError) -> Int {
    let queue = self.blockingQueue()
    return try await withContinuation(of: Int.self, throwing: IOError.self) {
      (continuation, awaiter) async throws(IOError) -> Int in
      let id = unsafe queue.submit(
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
