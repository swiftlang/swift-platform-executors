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

@Suite
struct TCPSocketTests {
  @available(anyAppleOS 27.0, *)
  private static let loopback = SocketAddress.v4(SocketAddress.V4(address: .loopback, port: 0))

  @Test
  @available(anyAppleOS 27.0, *)
  func bindReportsThePickedPort() async throws {
    try await PThreadExecutor.withExecutor(name: "TCPSocketTest") { executor in
      try await withOperationScheduler(executor) {
        let listener = try await TCPListener.bind(to: Self.loopback)
        let address = try listener.localAddress
        try await listener.close()

        guard case .v4(let v4) = address else {
          Issue.record("Expected an IPv4 address but got \(address)")
          return
        }
        #expect(v4.address == .loopback)
        #expect(v4.port != 0)
      }
    }
  }

  @Test
  @available(anyAppleOS 27.0, *)
  func connectToRefusedPortFails() async throws {
    try await PThreadExecutor.withExecutor(name: "TCPSocketTest") { executor in
      try await withOperationScheduler(executor) {
        try await withRefusingAddress { address in
          await #expect(throws: IOError.self) {
            let socket = try await TCPConnection.connect(to: address)
            try await socket.close()
          }
        }
      }
    }
  }

  @Test
  @available(anyAppleOS 27.0, *)
  func echoWithOperationScheduler() async throws {
    try await PThreadExecutor.withExecutor(name: "TCPSocketTest") { executor in
      try await withOperationScheduler(executor) {
        try await Self.echo()
      }
    }
  }

  @Test(arguments: [1, 4])
  @available(anyAppleOS 27.0, *)
  func echoWithPThreadTaskExecutorPreference(poolSize: Int) async throws {
    try await PThreadTaskExecutor.withExecutor(name: "TCPSocketTest", poolSize: poolSize) { executor in
      try await withTaskExecutorPreference(executor) {
        try await Self.echo()
      }
    }
  }

  @Test
  @available(anyAppleOS 27.0, *)
  func echoWithTaskExecutorPreference() async throws {
    try await PThreadExecutor.withExecutor(name: "TCPSocketTest") { executor in
      try await withTaskExecutorPreference(executor) {
        try await Self.echo()
      }
    }
  }

  @Test
  @available(anyAppleOS 27.0, *)
  func acceptOnACancelledTaskResumesWithCancelled() async throws {
    try await PThreadExecutor.withExecutor(name: "TCPSocketTest") { executor in
      try await withOperationScheduler(executor) {
        try await withThrowingTaskGroup { group in
          group.addTask {
            let listener = try await TCPListener.bind(to: Self.loopback)

            // The task is cancelled before the accept is submitted.
            withUnsafeCurrentTask { $0?.cancel() }
            let error = await #expect(throws: IOError.self) {
              let socket = try await listener.accept()
              try await socket.close()
            }
            #expect(error?.code == .cancelled)

            // Closing is not cancellable, so it still closes the listener.
            try await listener.close()
          }
          try await group.waitForAll()
        }
      }
    }
  }

  @Test
  @available(anyAppleOS 27.0, *)
  func cancellingAPendingAcceptResumesWithCancelled() async throws {
    try await PThreadExecutor.withExecutor(name: "TCPSocketTest") { executor in
      try await withOperationScheduler(executor) {
        try await Self.cancelPendingAccept()
      }
    }
  }

  @Test(arguments: [1, 4])
  @available(anyAppleOS 27.0, *)
  func cancellingAPendingAcceptOnTheExecutorResumesWithCancelled(poolSize: Int) async throws {
    // The task that cancels runs on the executor, so the cancellation
    // reaches the backend directly instead of through the executor's queue.
    try await PThreadTaskExecutor.withExecutor(name: "TCPSocketTest", poolSize: poolSize) { executor in
      try await withTaskExecutorPreference(executor) {
        try await Self.cancelPendingAccept()
      }
    }
  }

  /// Cancels an accept that waits for a connection that never comes.
  @available(anyAppleOS 27.0, *)
  private static func cancelPendingAccept() async throws {
    let (bound, boundContinuation) = AsyncStream.makeStream(of: Void.self)

    try await withThrowingTaskGroup { group in
      group.addTask {
        let listener = try await TCPListener.bind(to: Self.loopback)
        boundContinuation.yield()

        // Nothing connects, so the accept waits until the task is cancelled.
        let error = await #expect(throws: IOError.self) {
          let socket = try await listener.accept()
          try await socket.close()
        }
        #expect(error?.code == .cancelled)

        // Closing is not cancellable, so it still closes the listener.
        try await listener.close()
      }

      for await _ in bound {
        break
      }
      group.cancelAll()
      try await group.waitForAll()
    }
  }

  @Test
  @available(anyAppleOS 27.0, *)
  func cancellingAPendingReadResumesWithCancelledAndKeepsTheConnection() async throws {
    try await PThreadExecutor.withExecutor(name: "TCPSocketTest") { executor in
      try await withOperationScheduler(executor) {
        let listener = try await TCPListener.bind(to: Self.loopback)
        var client = try await TCPConnection.connect(to: listener.localAddress)
        let payload = Array("Sent after the read was cancelled".utf8)
        let (cancelled, cancelledContinuation) = AsyncStream.makeStream(of: Void.self)

        try await withThrowingTaskGroup { group in
          // A noncopyable value cannot be consumed out of a closure capture, so the
          // connection is moved into the child task through an optional.
          var serverBox: TCPConnection? = try await listener.accept()
          group.addTask {
            var server = serverBox.take()!

            // Nothing was sent yet, so the read waits until the task is cancelled.
            let error = await #expect(throws: IOError.self) {
              _ = try await server.read(count: 1024)
            }
            #expect(error?.code == .cancelled)
            cancelledContinuation.yield()

            // The connection is still usable after the cancelled read, and the
            // shield keeps the next read from being cancelled while it waits.
            let received = try await withTaskCancellationShield { () async throws(IOError) -> [UInt8] in
              try await server.readUntilEndOfStream()
            }
            #expect(received == payload)
            try await server.close()
          }

          group.cancelAll()
          for await _ in cancelled {
            break
          }
          try await client.write(from: payload.span.bytes)
          try await client.shutdown(.write)
          try await group.waitForAll()
        }

        try await listener.close()
        try await client.close()
      }
    }
  }

  @Test(arguments: [1, 4])
  @available(anyAppleOS 27.0, *)
  func cancellingAPendingWriteResumesWithCancelled(poolSize: Int) async throws {
    try await PThreadTaskExecutor.withExecutor(name: "TCPSocketTest", poolSize: poolSize) { executor in
      try await withTaskExecutorPreference(executor) {
        let listener = try await TCPListener.bind(to: Self.loopback)
        // This is more than the socket buffers of both peers hold, and the
        // server never reads, so a write waits for space at some point.
        let payload = [UInt8](repeating: 0, count: 64 * 1024 * 1024)
        let (writing, writingContinuation) = AsyncStream.makeStream(of: Void.self)

        try await withThrowingTaskGroup { group in
          // A noncopyable value cannot be consumed out of a closure capture, so the
          // connection is moved into the child task through an optional.
          var clientBox: TCPConnection? = try await TCPConnection.connect(to: listener.localAddress)
          let server = try await listener.accept()
          group.addTask {
            var client = clientBox.take()!
            writingContinuation.yield()
            let error = await #expect(throws: IOError.self) {
              try await client.write(from: payload.span.bytes)
            }
            #expect(error?.code == .cancelled)
            try await client.close()
          }

          for await _ in writing {
            break
          }
          group.cancelAll()
          try await group.waitForAll()
          try await server.close()
        }

        try await listener.close()
      }
    }
  }

  @Test
  @available(anyAppleOS 27.0, *)
  func escalatingThePriorityOfAPendingAcceptKeepsItPending() async throws {
    try await PThreadExecutor.withExecutor(name: "TCPSocketTest") { executor in
      try await withOperationScheduler(executor) {
        let (addresses, addressesContinuation) = AsyncStream.makeStream(of: SocketAddress.self)

        let acceptingTask = Task(priority: .low) {
          let listener = try await TCPListener.bind(to: Self.loopback)
          addressesContinuation.yield(try listener.localAddress)

          // The priority is escalated while the accept waits, which must
          // neither fail nor complete it.
          let socket = try await listener.accept()
          try await socket.close()
          try await listener.close()
        }

        var addressIterator = addresses.makeAsyncIterator()
        let address = try #require(await addressIterator.next())
        acceptingTask.escalatePriority(to: .high)

        let client = try await TCPConnection.connect(to: address)
        try await acceptingTask.value
        try await client.close()
      }
    }
  }

  @Test
  @available(anyAppleOS 27.0, *)
  func droppingAListenerWithoutClosingItTraps() async throws {
    await #expect(processExitsWith: .failure) {
      try await PThreadExecutor.withExecutor(name: "TCPSocketTest") { executor in
        try await withOperationScheduler(executor) {
          let listener = try await TCPListener.bind(
            to: .v4(SocketAddress.V4(address: .loopback, port: 0))
          )
          _ = consume listener
        }
      }
    }
  }

  @Test
  @available(anyAppleOS 27.0, *)
  func bindingWithoutAnOperationSchedulerTraps() async throws {
    await #expect(processExitsWith: .failure) {
      let listener = try await TCPListener.bind(to: .v4(SocketAddress.V4(address: .loopback, port: 0)))
      try await listener.close()
    }
  }

  @Test(arguments: [1, 4])
  @available(anyAppleOS 27.0, *)
  func concurrentEcho(poolSize: Int) async throws {
    try await PThreadTaskExecutor.withExecutor(name: "TCPSocketTest", poolSize: poolSize) { executor in
      try await withTaskExecutorPreference(executor) {
        let listener = try await TCPListener.bind(to: Self.loopback)
        let address = try listener.localAddress
        // This is more than the socket buffers of both peers hold, so the
        // client deadlocks if it does not read the echo while it writes.
        let payload = (0..<(4 * 1024 * 1024)).map { UInt8(truncatingIfNeeded: $0) }

        try await withThrowingTaskGroup(of: [UInt8].self) { group in
          group.addTask {
            let client = try await TCPConnection.connect(to: address)
            let echoed = try await client.withSplit { readHalf, writeHalf in
              let (echoed, _) = try await withConcurrently {
                try await readHalf.readUntilEndOfStream()
              } _: {
                try await writeHalf.write(from: payload.span.bytes)
                try await writeHalf.shutdown()
              }
              return echoed
            }
            try await client.close()
            return echoed
          }

          var server = try await listener.accept()
          try await server.echoUntilEndOfStream()
          try await server.close()

          let echoed = try await group.next()
          #expect(echoed == payload)
        }

        try await listener.close()
      }
    }
  }

  /// Echoes a payload through a connection between a client and a server task.
  @available(anyAppleOS 27.0, *)
  private static func echo() async throws {
    let listener = try await TCPListener.bind(to: Self.loopback)
    let address = try listener.localAddress
    let payload = Array("Hello from the high level TCP socket".utf8)

    try await withThrowingTaskGroup(of: [UInt8].self) { group in
      group.addTask {
        var client = try await TCPConnection.connect(to: address)
        try await client.write(from: payload.span.bytes)
        try await client.shutdown(.write)
        let echoed = try await client.readUntilEndOfStream()
        try await client.close()
        return echoed
      }

      var server = try await listener.accept()
      let received = try await server.readUntilEndOfStream()
      try await server.write(from: received.span.bytes)
      try await server.close()

      #expect(received == payload)
      let echoed = try await group.next()
      #expect(echoed == payload)
    }

    try await listener.close()
  }
}

@available(anyAppleOS 27.0, *)
extension TCPConnection {
  /// Reads once, returning at most `count` bytes, or none at the end of the stream.
  fileprivate mutating func read(count: Int) async throws(IOError) -> [UInt8] {
    // The buffer has to stay alive while the read is in flight so we heap alloc here.
    let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: count, alignment: 1)
    defer {
      buffer.deallocate()
    }

    var output = OutputRawSpan(buffer: buffer, initializedCount: 0)
    let received = try await self.read(into: &output)
    _ = output.finalize(for: buffer)
    return Array(UnsafeRawBufferPointer(rebasing: buffer[..<received]))
  }

  /// Reads until the peer closed its side of the connection.
  fileprivate mutating func readUntilEndOfStream() async throws(IOError) -> [UInt8] {
    // The buffer has to stay alive while the read is in flight so we heap alloc here.
    let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 1024, alignment: 1)
    defer {
      buffer.deallocate()
    }

    var received = [UInt8]()
    while true {
      var output = OutputRawSpan(buffer: buffer, initializedCount: 0)
      let count = try await self.read(into: &output)
      let initializedCount = output.finalize(for: buffer)
      #expect(initializedCount == count)

      if count == 0 {
        return received
      }
      received += UnsafeRawBufferPointer(rebasing: buffer[..<count])
    }
  }
}

@available(anyAppleOS 27.0, *)
extension TCPConnection {
  /// Writes everything back that the peer sends until it closes its side of the connection.
  fileprivate mutating func echoUntilEndOfStream() async throws(IOError) {
    // The buffer has to stay alive while the read is in flight so we heap alloc here.
    let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 64 * 1024, alignment: 1)
    defer {
      buffer.deallocate()
    }

    while true {
      var output = OutputRawSpan(buffer: buffer, initializedCount: 0)
      let count = try await self.read(into: &output)
      _ = output.finalize(for: buffer)
      if count == 0 {
        return
      }
      try await self.write(from: RawSpan(_unsafeBytes: UnsafeRawBufferPointer(rebasing: buffer[..<count])))
    }
  }
}

@available(anyAppleOS 27.0, *)
extension TCPConnection.ReadHalf {
  /// Reads until the peer closed its side of the connection.
  fileprivate func readUntilEndOfStream() async throws(IOError) -> [UInt8] {
    // The buffer has to stay alive while the read is in flight so we heap alloc here.
    let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 64 * 1024, alignment: 1)
    defer {
      buffer.deallocate()
    }

    var received = [UInt8]()
    while true {
      var output = OutputRawSpan(buffer: buffer, initializedCount: 0)
      let count = try await self.read(into: &output)
      _ = output.finalize(for: buffer)
      if count == 0 {
        return received
      }
      received += UnsafeRawBufferPointer(rebasing: buffer[..<count])
    }
  }
}

#endif
#endif
