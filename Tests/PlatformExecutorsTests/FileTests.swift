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

import Testing
@_spi(ExperimentalScheduling) @_spi(ConcurrencyExecutors) @_spi(ExperimentalCustomExecutors) import _Concurrency
@_spi(ExperimentalScheduling) @_spi(ConcurrencyExecutors) @_spi(ExperimentalCustomExecutors) import PlatformExecutors

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

@Suite
struct FileTests {
  @available(anyAppleOS 27.0, *)
  private static func withTemporaryFile(
    ioBackend: PThreadIOBackend,
    poolSize: Int = 1,
    _ body: (String) async throws -> Void
  ) async throws {
    let path = "/tmp/platform-executors-file-test-\(UInt64.random(in: .min ... .max))"
    // TODO: Offer an unlink operation and use it here
    defer { unsafe unlink(path) }
    try await PThreadTaskExecutor.withExecutor(name: "FileTest", poolSize: poolSize, ioBackend: ioBackend) {
      executor in
      try await withTaskExecutorPreference(executor) {
        try await body(path)
      }
    }
  }

  @Test(arguments: PThreadIOBackend.tested)
  @available(anyAppleOS 27.0, *)
  func writeAndReadBack(ioBackend: PThreadIOBackend) async throws {
    try await Self.withTemporaryFile(ioBackend: ioBackend) { path in
      let payload = Array("Hello from the high level file".utf8)

      let file = try await File.open(path: path)
      try await file.write(from: payload.span.bytes, at: 0)
      #expect(try await file.readAll() == payload)
      try await file.close()
    }
  }

  @Test(arguments: PThreadIOBackend.tested)
  @available(anyAppleOS 27.0, *)
  func readsAndWritesAtOffsets(ioBackend: PThreadIOBackend) async throws {
    try await Self.withTemporaryFile(ioBackend: ioBackend) { path in
      let file = try await File.open(path: path)
      try await file.write(from: Array("0123456789".utf8).span.bytes, at: 0)
      try await file.write(from: Array("abc".utf8).span.bytes, at: 4)
      #expect(try await file.readAll() == Array("0123abc789".utf8))

      #expect(try await file.read(length: 3, at: 7) == Array("789".utf8))

      // Reading at the end of the file reports the end.
      #expect(try await file.read(length: 3, at: 10).isEmpty)
      try await file.close()
    }
  }

  @Test(arguments: PThreadIOBackend.tested)
  @available(anyAppleOS 27.0, *)
  func writesLargeBuffers(ioBackend: PThreadIOBackend) async throws {
    try await Self.withTemporaryFile(ioBackend: ioBackend) { path in
      let payload = (0..<(3 * 1024 * 1024 + 17)).map { UInt8(truncatingIfNeeded: $0 &* 31) }

      let file = try await File.open(path: path)
      try await file.write(from: payload.span.bytes, at: 0)
      #expect(try await file.readAll() == payload)
      try await file.close()
    }
  }

  @Test(arguments: PThreadIOBackend.tested)
  @available(anyAppleOS 27.0, *)
  func truncateDropsTheExistingContent(ioBackend: PThreadIOBackend) async throws {
    try await Self.withTemporaryFile(ioBackend: ioBackend) { path in
      let writable = try await File.Writable.open(path: path)
      try await writable.write(from: Array("old content".utf8).span.bytes, at: 0)
      try await writable.close()

      let file = try await File.open(path: path, options: .newFile(replaceExisting: true))
      try await file.write(from: Array("new".utf8).span.bytes, at: 0)
      #expect(try await file.readAll() == Array("new".utf8))
      try await file.close()
    }
  }

  @Test(arguments: PThreadIOBackend.tested)
  @available(anyAppleOS 27.0, *)
  func openingAMissingFileFails(ioBackend: PThreadIOBackend) async throws {
    try await Self.withTemporaryFile(ioBackend: ioBackend) { path in
      let error = await #expect(throws: IOError.self) {
        let file = try await File.Readable.open(path: path)
        try await file.close()
      }
      #expect(error?.code.platformCode == ENOENT)
    }
  }

  @Test(arguments: PThreadIOBackend.tested)
  @available(anyAppleOS 27.0, *)
  func exclusiveCreateFailsForExistingFiles(ioBackend: PThreadIOBackend) async throws {
    try await Self.withTemporaryFile(ioBackend: ioBackend) { path in
      let file = try await File.Writable.open(path: path)
      try await file.close()

      let error = await #expect(throws: IOError.self) {
        let file = try await File.Writable.open(path: path)
        try await file.close()
      }
      #expect(error?.code.platformCode == EEXIST)
    }
  }

  @Test(arguments: PThreadIOBackend.tested)
  @available(anyAppleOS 27.0, *)
  func readableAndWritableFilesShareTheContent(ioBackend: PThreadIOBackend) async throws {
    try await Self.withTemporaryFile(ioBackend: ioBackend) { path in
      let writable = try await File.Writable.open(path: path)
      try await writable.write(from: Array("written".utf8).span.bytes, at: 0)
      try await writable.close()

      let readable = try await File.Readable.open(path: path)
      #expect(try await readable.readAll() == Array("written".utf8))
      try await readable.close()
    }
  }

  @Test(arguments: PThreadIOBackend.tested)
  @available(anyAppleOS 27.0, *)
  func modifyFileKeepsTheContentAndCanCreate(ioBackend: PThreadIOBackend) async throws {
    try await Self.withTemporaryFile(ioBackend: ioBackend) { path in
      // The file doesn't exist, and is not created.
      let error = await #expect(throws: IOError.self) {
        let file = try await File.Writable.open(path: path, options: .modifyFile(createIfNecessary: false))
        try await file.close()
      }
      #expect(error?.code.platformCode == ENOENT)

      var file = try await File.Writable.open(path: path, options: .modifyFile(createIfNecessary: true))
      try await file.write(from: Array("0123456789".utf8).span.bytes, at: 0)
      try await file.close()

      // It is opened without dropping the content this time.
      file = try await File.Writable.open(path: path, options: .modifyFile(createIfNecessary: true))
      try await file.write(from: Array("abc".utf8).span.bytes, at: 2)
      try await file.close()

      let readable = try await File.Readable.open(path: path)
      #expect(try await readable.readAll() == Array("01abc56789".utf8))
      try await readable.close()
    }
  }

  @Test(arguments: PThreadIOBackend.tested)
  @available(anyAppleOS 27.0, *)
  func newFileAppliesThePermissions(ioBackend: PThreadIOBackend) async throws {
    try await Self.withTemporaryFile(ioBackend: ioBackend) { path in
      let file = try await File.Writable.open(
        path: path,
        options: .newFile(replaceExisting: false, permissions: [.ownerRead, .ownerWrite, .groupRead])
      )
      try await file.close()

      // TODO: Offer a stat operation and use it here
      var status = stat()
      unsafe #expect(stat(path, &status) == 0)
      // The umask can only remove bits.
      #expect(status.st_mode & 0o777 & ~0o640 == 0)
      #expect(status.st_mode & 0o600 == 0o600)
    }
  }

  @Test(arguments: PThreadIOBackend.tested)
  @available(anyAppleOS 27.0, *)
  func notFollowingSymbolicLinksFailsForALink(ioBackend: PThreadIOBackend) async throws {
    try await Self.withTemporaryFile(ioBackend: ioBackend) { path in
      let file = try await File.Writable.open(path: path)
      try await file.close()
      let link = path + "-link"
      // TODO: Offer a symlink operation and use it here
      unsafe #expect(symlink(path, link) == 0)
      // TODO: Offer an unlink operation and use it here
      defer { unsafe unlink(link) }

      let linked = try await File.Readable.open(path: link)
      try await linked.close()

      await #expect(throws: IOError.self) {
        let file = try await File.Readable.open(path: link, options: .init(followSymbolicLinks: false))
        try await file.close()
      }
    }
  }

  @Test(arguments: PThreadIOBackend.tested)
  @available(anyAppleOS 27.0, *)
  func openOnACancelledTaskResumesWithCancelled(ioBackend: PThreadIOBackend) async throws {
    try await Self.withTemporaryFile(ioBackend: ioBackend) { path in
      try await withThrowingTaskGroup { group in
        group.addTask {
          unsafe withUnsafeCurrentTask { unsafe $0?.cancel() }
          let error = await #expect(throws: IOError.self) {
            let file = try await File.Writable.open(path: path)
            try await file.close()
          }
          #expect(error?.code == .cancelled)
        }
        try await group.waitForAll()
      }
    }
  }

  /// Cancelling a task whose blocking operation still waits for a free thread resumes it right away.
  ///
  /// The only thread of the blocking pool is held in an \`open\` of a FIFO that has no writer.
  @Test(arguments: PThreadIOBackend.tested.filter { $0.description != "ioUring" })
  @available(anyAppleOS 27.0, *)
  func cancellingAQueuedOperationResumesWithCancelled(ioBackend: PThreadIOBackend) async throws {
    let fifo = "/tmp/platform-executors-file-test-fifo-\(UInt64.random(in: .min ... .max))"
    // TODO: Offer a mkfifo operation and use it here
    unsafe #expect(mkfifo(fifo, 0o600) == 0)
    // TODO: Offer an unlink operation and use it here
    defer { unsafe unlink(fifo) }
    let regular = "/tmp/platform-executors-file-test-\(UInt64.random(in: .min ... .max))"
    // TODO: Offer an unlink operation and use it here
    defer { unsafe unlink(regular) }

    try await PThreadTaskExecutor.withExecutor(
      name: "FileTest",
      poolSize: 1,
      ioBackend: ioBackend,
      blockingPoolSize: 1
    ) { executor in
      try await withTaskExecutorPreference(executor) {
        // Occupies the only blocking thread until a writer opens the FIFO.
        let blocker = Task(executorPreference: executor) {
          let file = try await File.Readable.open(path: fifo)
          try await file.close()
        }
        try await Task.sleep(for: .milliseconds(200))

        let queued = Task(executorPreference: executor) {
          let file = try await File.Writable.open(path: regular)
          try await file.close()
        }
        try await Task.sleep(for: .milliseconds(200))
        queued.cancel()

        // If the cancellation does not work this releases the blocking thread
        // after a while instead of being stuck in the test, and the queued
        // operation then completes without being cancelled.
        let watchdog = Task.detached {
          try await Task.sleep(for: .seconds(5))
          Self.releaseFIFO(fifo)
        }
        let queuedResult = await queued.result
        watchdog.cancel()
        if case .failure(let error) = queuedResult {
          #expect((error as? IOError)?.code == .cancelled)
        } else {
          Issue.record("The queued operation was not cancelled while it waited for a thread")
        }

        // The operation that holds the thread cannot be interrupted, it completes once the FIFO has a writer.
        Self.releaseFIFO(fifo)
        try await blocker.value
      }
    }
  }

  /// Opens the write end of a FIFO, which lets a reader that waits in an \`open\` continue.
  private static func releaseFIFO(_ path: String) {
    let descriptor = unsafe open(path, O_WRONLY | O_NONBLOCK)
    if descriptor >= 0 {
      close(descriptor)
    }
  }

  @Test(arguments: PThreadIOBackend.tested, [1, 4])
  @available(anyAppleOS 27.0, *)
  func manyFilesConcurrently(ioBackend: PThreadIOBackend, poolSize: Int) async throws {
    try await Self.withTemporaryFile(ioBackend: ioBackend, poolSize: poolSize) { path in
      try await withThrowingTaskGroup { group in
        for index in 0..<32 {
          group.addTask {
            let path = "\(path)-\(index)"
            defer { unsafe unlink(path) }
            let payload = Array(repeating: UInt8(index), count: 10_000 + index)
            let file = try await File.open(path: path)
            try await file.write(from: payload.span.bytes, at: 0)
            #expect(try await file.readAll() == payload)
            try await file.close()
          }
        }
        try await group.waitForAll()
      }
    }
  }

  @Test(
    .disabled("Leasing buffers is not implemented in the executors yet"),
    arguments: PThreadIOBackend.tested
  )
  @available(anyAppleOS 27.0, *)
  func readAndWriteWithBuffersFromTheExecutor(ioBackend: PThreadIOBackend) async throws {
    try await Self.withTemporaryFile(ioBackend: ioBackend) { path in
      let writable = try await File.Writable.open(path: path, options: .newFile(replaceExisting: true))
      try await writable.write(at: 0) { span in span.append(bytes: Array("readable and writable".utf8)) }
      try await writable.close()

      let readable = try await File.Readable.open(path: path)
      #expect(try await readable.read(at: 0) { span in span.bytesArray() } == Array("readable and writable".utf8))
      try await readable.close()
    }
  }
}

#endif
#endif
