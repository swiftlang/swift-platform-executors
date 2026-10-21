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
@_spi(ExperimentalScheduling) @_spi(ConcurrencyExecutors) @_spi(ExperimentalCustomExecutors) import PlatformExecutors
@_spi(ExperimentalScheduling) @_spi(ConcurrencyExecutors) @_spi(ExperimentalCustomExecutors) import _Concurrency

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Writes a file, modifies it, and reads it back in several ways.
@main
@available(anyAppleOS 27.0, *)
struct FileExample {
  static func main() async throws {
    let path = "/tmp/file-example-\(getpid()).txt"
    // TODO: We need to offer this operation in the future.
    defer { unsafe unlink(path) }

    try await PThreadTaskExecutor.withExecutor(
      name: "File",
      poolSize: 2,
      blockingPoolSize: 2
    ) { executor in
      try await withTaskExecutorPreference(executor) {
        try await Self.write(to: path)
        try await Self.modify(path)
        try await Self.readBack(path)
        try await Self.readConcurrently(path)
        try await Self.useReadWriteFile(path)
      }
    }
    print("Done")
  }

  /// Creates a file for writing.
  ///
  /// Opening fails if the file exists already, unless the options say otherwise.
  private static func write(to path: String) async throws {
    let file = try await File.Writable.open(
      path: path,
      options: .newFile(replaceExisting: true)
    )
    try await file.write(
      from: Array("Hello from the file example. ".utf8).span.bytes,
      at: 0
    )
    try await file.close()
    print("Wrote the file")
  }

  /// Overwrites a region of an existing file, which keeps the rest of its content.
  private static func modify(_ path: String) async throws {
    let file = try await File.Writable.open(
      path: path,
      options: .modifyFile(createIfNecessary: false)
    )
    try await file.write(from: Array("HELLO".utf8).span.bytes, at: 0)
    try await file.close()
    print("Modified the file")
  }

  /// Reads the file from its start until its end.
  private static func readBack(_ path: String) async throws {
    let file = try await File.Readable.open(path: path)
    let contents = try await file.readAll()
    print("Read \(contents.count) bytes: \(String(decoding: contents, as: UTF8.self))")
    try await file.close()
  }

  /// Reads two regions of the file at the same time.
  private static func readConcurrently(_ path: String) async throws {
    try await withThrowingTaskGroup(of: String.self) { group in
      for (offset, length) in [(Int64(0), 5), (Int64(6), 4)] {
        group.addTask {
          let file = try await File.Readable.open(path: path)
          let region = String(
            decoding: try await file.read(length: length, at: offset),
            as: UTF8.self
          )
          try await file.close()
          return region
        }
      }
      for try await region in group {
        print("Read the region \"\(region)\"")
      }
    }
  }

  /// A `File` reads and writes. Use `File.Readable` and `File.Writable` if one direction is enough.
  private static func useReadWriteFile(_ path: String) async throws {
    let file = try await File.open(
      path: path,
      options: .modifyFile(createIfNecessary: false)
    )
    try await file.write(from: Array("THE".utf8).span.bytes, at: 11)
    print("Read the region \"\(String(decoding: try await file.read(length: 15, at: 6), as: UTF8.self))\"")
    try await file.close()
  }
}
#else
@main
struct FileExample {
  static func main() {
    print("The file example requires the ExperimentalIO trait on Linux, FreeBSD or Darwin.")
  }
}
#endif
