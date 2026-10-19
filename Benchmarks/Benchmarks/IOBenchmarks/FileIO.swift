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

import BasicContainers
import Benchmark
import PlatformExecutors

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// The size of every sequential read and write.
private let chunkSize = 64 * 1024

/// The size of the reads and writes that stress the cost of a single operation.
private let smallSize = 4 * 1024

/// Returns a path for a file that doesn't exist yet.
private func makeBenchmarkPath(_ name: String) -> String {
  "/tmp/platform-executors-benchmark-\(getpid())-\(name)-\(UInt32.random(in: .min ... .max))"
}

/// Fills a new file with the given number of bytes, outside of any measurement.
@available(anyAppleOS 27.0, *)
private func makeFile(at path: String, size: Int) async throws {
  let chunk = [UInt8](repeating: 0x5a, count: chunkSize)
  let file = try await File.Writable.open(path: path, options: .newFile(replaceExisting: true))
  var offset = 0
  while offset < size {
    let count = min(chunkSize, size - offset)
    try await file.write(from: chunk.span.bytes.extracting(first: count), at: Int64(offset))
    offset += count
  }
  try await file.close()
}

/// Runs the body on a task executor with the given I/O backend.
@available(anyAppleOS 27.0, *)
private func withFileExecutor(
  _ name: String,
  poolSize: Int = 1,
  blockingPoolSize: Int = 4,
  ioBackend: PThreadIOBackend,
  _ body: () async throws -> Void
) async throws {
  try await PThreadTaskExecutor.withExecutor(
    name: name,
    poolSize: poolSize,
    ioBackend: ioBackend,
    blockingPoolSize: blockingPoolSize
  ) { executor in
    try await withTaskExecutorPreference(executor) {
      try await body()
    }
  }
}

/// Appends chunks to a new file.
///
/// - Parameters:
///   - numberOfChunks: The number of 64 KiB chunks to write.
///   - ioBackend: The I/O backend that the executor's threads use.
///   - benchmark: The benchmark to measure.
@available(anyAppleOS 27.0, *)
func runFileSequentialWrite(numberOfChunks: Int, ioBackend: PThreadIOBackend, benchmark: Benchmark) async throws {
  let path = makeBenchmarkPath("write")
  defer { unlink(path) }
  let chunk = [UInt8](repeating: 0x5a, count: chunkSize)

  try await withFileExecutor("FileSequentialWrite", ioBackend: ioBackend) {
    let file = try await File.Writable.open(path: path, options: .newFile(replaceExisting: true))

    benchmark.startMeasurement()
    for index in 0..<numberOfChunks {
      try await file.write(from: chunk.span.bytes, at: Int64(index * chunkSize))
    }
    benchmark.stopMeasurement()

    try await file.close()
  }
}

/// Reads a file from start to end in chunks.
///
/// - Parameters:
///   - numberOfChunks: The number of 64 KiB chunks to read.
///   - ioBackend: The I/O backend that the executor's threads use.
///   - benchmark: The benchmark to measure.
@available(anyAppleOS 27.0, *)
func runFileSequentialRead(numberOfChunks: Int, ioBackend: PThreadIOBackend, benchmark: Benchmark) async throws {
  let path = makeBenchmarkPath("read")
  defer { unlink(path) }

  try await withFileExecutor("FileSequentialRead", ioBackend: ioBackend) {
    try await makeFile(at: path, size: numberOfChunks * chunkSize)
    let file = try await File.Readable.open(path: path)
    var buffer = UniqueArray<UInt8>(minimumCapacity: chunkSize)

    benchmark.startMeasurement()
    for index in 0..<numberOfChunks {
      buffer.removeAll()
      let count = try await buffer.append(addingByteCount: chunkSize) { output in
        try await file.read(into: &output, at: Int64(index * chunkSize))
      }
      precondition(count == chunkSize, "A read returned fewer bytes than the file has")
    }
    benchmark.stopMeasurement()

    try await file.close()
  }
}

/// Reads small blocks from pseudo random offsets of a file that is in the page cache.
///
/// - Parameters:
///   - numberOfReads: The number of 4 KiB reads.
///   - ioBackend: The I/O backend that the executor's threads use.
///   - benchmark: The benchmark to measure.
@available(anyAppleOS 27.0, *)
func runFileSmallReads(numberOfReads: Int, ioBackend: PThreadIOBackend, benchmark: Benchmark) async throws {
  let fileSize = 4 * 1024 * 1024
  let path = makeBenchmarkPath("small-reads")
  defer { unlink(path) }

  try await withFileExecutor("FileSmallReads", ioBackend: ioBackend) {
    try await makeFile(at: path, size: fileSize)
    let file = try await File.Readable.open(path: path)
    var buffer = UniqueArray<UInt8>(minimumCapacity: smallSize)
    let blocks = fileSize / smallSize

    var state: UInt64 = 0x9E37_79B9_7F4A_7C15
    benchmark.startMeasurement()
    for _ in 0..<numberOfReads {
      // An xorshift generator keeps the offsets deterministic and allocation free.
      state ^= state << 13
      state ^= state >> 7
      state ^= state << 17
      let offset = Int64(Int(state % UInt64(blocks)) * smallSize)
      buffer.removeAll()
      let count = try await buffer.append(addingByteCount: smallSize) { output in
        try await file.read(into: &output, at: offset)
      }
      precondition(count == smallSize, "A read returned fewer bytes than the file has")
    }
    benchmark.stopMeasurement()

    try await file.close()
  }
}

/// Opens and closes the same file repeatedly.
///
/// - Parameters:
///   - numberOfFiles: The number of times to open and close the file.
///   - ioBackend: The I/O backend that the executor's threads use.
///   - benchmark: The benchmark to measure.
@available(anyAppleOS 27.0, *)
func runFileOpenClose(numberOfFiles: Int, ioBackend: PThreadIOBackend, benchmark: Benchmark) async throws {
  let path = makeBenchmarkPath("open-close")
  defer { unlink(path) }

  try await withFileExecutor("FileOpenClose", ioBackend: ioBackend) {
    try await makeFile(at: path, size: smallSize)

    benchmark.startMeasurement()
    for _ in 0..<numberOfFiles {
      let file = try await File.Readable.open(path: path)
      try await file.close()
    }
    benchmark.stopMeasurement()
  }
}

/// Reads many files concurrently, each by its own task.
///
/// - Parameters:
///   - tasks: The number of tasks, each reading its own file.
///   - readsPerTask: The number of 64 KiB reads of every task.
///   - poolSize: The number of threads of the `PThreadTaskExecutor` that the tasks run on.
///   - blockingPoolSize: The number of threads of the pool that performs blocking file operations.
///   - ioBackend: The I/O backend that the executor's threads use.
///   - benchmark: The benchmark to measure.
@available(anyAppleOS 27.0, *)
func runFileConcurrentReads(
  tasks: Int,
  readsPerTask: Int,
  poolSize: Int = 1,
  blockingPoolSize: Int,
  ioBackend: PThreadIOBackend,
  benchmark: Benchmark
) async throws {
  let paths = (0..<tasks).map { makeBenchmarkPath("concurrent-\($0)") }
  defer { paths.forEach { _ = unlink($0) } }

  try await withFileExecutor(
    "FileConcurrentReads",
    poolSize: poolSize,
    blockingPoolSize: blockingPoolSize,
    ioBackend: ioBackend
  ) {
    for path in paths {
      try await makeFile(at: path, size: readsPerTask * chunkSize)
    }

    benchmark.startMeasurement()
    try await withThrowingTaskGroup { group in
      for path in paths {
        group.addTask {
          let file = try await File.Readable.open(path: path)
          var buffer = UniqueArray<UInt8>(minimumCapacity: chunkSize)
          for index in 0..<readsPerTask {
            buffer.removeAll()
            let count = try await buffer.append(addingByteCount: chunkSize) { output in
              try await file.read(into: &output, at: Int64(index * chunkSize))
            }
            precondition(count == chunkSize, "A read returned fewer bytes than the file has")
          }
          try await file.close()
        }
      }
      try await group.waitForAll()
    }
    benchmark.stopMeasurement()
  }
}
