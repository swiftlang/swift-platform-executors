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
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// An identity of the calling thread.
private func currentThreadIdentity() -> UInt {
  #if canImport(Darwin)
  // Darwin imports `pthread_t` as a pointer.
  let thread = unsafe pthread_self()
  #else
  let thread = pthread_self()
  #endif
  return withUnsafeBytes(of: thread) { unsafe $0.load(as: UInt.self) }
}

@Suite
struct TCPSocketTests {
  @available(anyAppleOS 27.0, *)
  private static let loopback = SocketAddress.v4(SocketAddress.V4(address: .loopback, port: 0))

  @Test(arguments: PThreadIOBackend.tested)
  @available(anyAppleOS 27.0, *)
  func bindReportsThePickedPort(ioBackend: PThreadIOBackend) async throws {
    try await PThreadExecutor.withExecutor(name: "TCPSocketTest", ioBackend: ioBackend) { executor in
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

  @Test(arguments: PThreadIOBackend.tested)
  @available(anyAppleOS 27.0, *)
  func connectToRefusedPortFails(ioBackend: PThreadIOBackend) async throws {
    try await PThreadExecutor.withExecutor(name: "TCPSocketTest", ioBackend: ioBackend) { executor in
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

  @Test(arguments: PThreadIOBackend.tested)
  @available(anyAppleOS 27.0, *)
  func echoWithOperationScheduler(ioBackend: PThreadIOBackend) async throws {
    try await PThreadExecutor.withExecutor(name: "TCPSocketTest", ioBackend: ioBackend) { executor in
      try await withOperationScheduler(executor) {
        try await Self.echo()
      }
    }
  }

  @Test(arguments: PThreadIOBackend.tested, [1, 4])
  @available(anyAppleOS 27.0, *)
  func echoWithPThreadTaskExecutorPreference(ioBackend: PThreadIOBackend, poolSize: Int) async throws {
    try await PThreadTaskExecutor.withExecutor(name: "TCPSocketTest", poolSize: poolSize, ioBackend: ioBackend) {
      executor in
      try await withTaskExecutorPreference(executor) {
        try await Self.echo()
      }
    }
  }

  @Test(arguments: PThreadIOBackend.tested)
  @available(anyAppleOS 27.0, *)
  func echoWithTaskExecutorPreference(ioBackend: PThreadIOBackend) async throws {
    try await PThreadExecutor.withExecutor(name: "TCPSocketTest", ioBackend: ioBackend) { executor in
      try await withTaskExecutorPreference(executor) {
        try await Self.echo()
      }
    }
  }

  @Test(arguments: PThreadIOBackend.tested)
  @available(anyAppleOS 27.0, *)
  func acceptOnACancelledTaskResumesWithCancelled(ioBackend: PThreadIOBackend) async throws {
    try await PThreadExecutor.withExecutor(name: "TCPSocketTest", ioBackend: ioBackend) { executor in
      try await withOperationScheduler(executor) {
        try await withThrowingTaskGroup { group in
          group.addTask {
            let listener = try await TCPListener.bind(to: Self.loopback)

            // The task is cancelled before the accept is submitted.
            unsafe withUnsafeCurrentTask { unsafe $0?.cancel() }
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

  @Test(arguments: PThreadIOBackend.tested)
  @available(anyAppleOS 27.0, *)
  func cancellingAPendingAcceptResumesWithCancelled(ioBackend: PThreadIOBackend) async throws {
    try await PThreadExecutor.withExecutor(name: "TCPSocketTest", ioBackend: ioBackend) { executor in
      try await withOperationScheduler(executor) {
        try await Self.cancelPendingAccept()
      }
    }
  }

  @Test(arguments: PThreadIOBackend.tested, [1, 4])
  @available(anyAppleOS 27.0, *)
  func cancellingAPendingAcceptOnTheExecutorResumesWithCancelled(
    ioBackend: PThreadIOBackend,
    poolSize: Int
  ) async throws {
    // The task that cancels runs on the executor, so the cancellation
    // reaches the backend directly instead of through the executor's queue.
    try await PThreadTaskExecutor.withExecutor(name: "TCPSocketTest", poolSize: poolSize, ioBackend: ioBackend) {
      executor in
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

  @Test(arguments: PThreadIOBackend.tested)
  @available(anyAppleOS 27.0, *)
  func cancellingAPendingReadResumesWithCancelledAndKeepsTheConnection(ioBackend: PThreadIOBackend) async throws {
    try await PThreadExecutor.withExecutor(name: "TCPSocketTest", ioBackend: ioBackend) { executor in
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

  @Test(arguments: PThreadIOBackend.tested, [1, 4])
  @available(anyAppleOS 27.0, *)
  func cancellingAPendingWriteResumesWithCancelled(ioBackend: PThreadIOBackend, poolSize: Int) async throws {
    try await PThreadTaskExecutor.withExecutor(name: "TCPSocketTest", poolSize: poolSize, ioBackend: ioBackend) {
      executor in
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

  @Test(arguments: PThreadIOBackend.tested)
  @available(anyAppleOS 27.0, *)
  func escalatingThePriorityOfAPendingAcceptKeepsItPending(ioBackend: PThreadIOBackend) async throws {
    try await PThreadExecutor.withExecutor(name: "TCPSocketTest", ioBackend: ioBackend) { executor in
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

  @Test(arguments: PThreadIOBackend.tested)
  @available(anyAppleOS 27.0, *)
  func connectionsAreUsedOnOtherExecutorsOfThePoolThanTheOneThatAcceptedThem(
    ioBackend: PThreadIOBackend
  ) async throws {
    let connections = 16
    try await PThreadTaskExecutor.withExecutor(name: "TCPSocketTest", poolSize: 4, ioBackend: ioBackend) { executor in
      try await withTaskExecutorPreference(executor) {
        let listener = try await TCPListener.bind(to: Self.loopback)
        let address = try listener.localAddress
        let payload = Array("Hello from a connection that moved".utf8)

        try await withThrowingTaskGroup(of: [UInt8].self) { group in
          for _ in 0..<connections {
            group.addTask {
              var client = try await TCPConnection.connect(to: address)
              try await client.write(from: payload.span.bytes)
              try await client.shutdown(.write)
              let echoed = try await client.readUntilEndOfStream()
              try await client.close()
              return echoed
            }
          }

          // This task only accepts. Every connection is echoed by a task of its own, which the pool runs on
          // another executor than the one that accepted the connection.
          try await withThrowingTaskGroup { servers in
            for _ in 0..<connections {
              var acceptedBox: TCPConnection? = try await listener.accept()
              servers.addTask {
                var accepted = acceptedBox.take()!
                try await accepted.echoUntilEndOfStream()
                try await accepted.close()
              }
            }
            try await servers.waitForAll()
          }

          for try await echoed in group {
            #expect(echoed == payload)
          }
        }

        try await listener.close()
      }
    }
  }

  @Test(arguments: PThreadIOBackend.tested)
  @available(anyAppleOS 27.0, *)
  func operationsOfAPoolStayOnTheThreadOfTheTask(ioBackend: PThreadIOBackend) async throws {
    let tasks = 32
    try await PThreadTaskExecutor.withExecutor(name: "TCPSocketTest", poolSize: 4, ioBackend: ioBackend) { executor in
      try await withTaskExecutorPreference(executor) {
        let listener = try await TCPListener.bind(to: Self.loopback)
        let address = try listener.localAddress

        try await withThrowingTaskGroup(of: Bool.self) { group in
          for _ in 0..<tasks {
            group.addTask {
              // Connecting to a listener waits for the handshake, so the task suspends and resumes where the
              // pool performed the operation.
              let before = currentThreadIdentity()
              let client = try await TCPConnection.connect(to: address)
              let after = currentThreadIdentity()
              try await client.close()
              return before == after
            }
          }

          for _ in 0..<tasks {
            let accepted = try await listener.accept()
            try await accepted.close()
          }

          for try await stayedOnTheThread in group {
            #expect(stayedOnTheThread)
          }
        }

        try await listener.close()
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

  @Test(arguments: PThreadIOBackend.tested, [1, 4])
  @available(anyAppleOS 27.0, *)
  func concurrentEcho(ioBackend: PThreadIOBackend, poolSize: Int) async throws {
    try await PThreadTaskExecutor.withExecutor(name: "TCPSocketTest", poolSize: poolSize, ioBackend: ioBackend) {
      executor in
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

  @Test(
    .disabled("Leasing buffers is not implemented in the executors yet"),
    arguments: PThreadIOBackend.tested
  )
  @available(anyAppleOS 27.0, *)
  func roundTripWithBuffersFromTheExecutor(ioBackend: PThreadIOBackend) async throws {
    try await PThreadExecutor.withExecutor(name: "TCPSocketTest", ioBackend: ioBackend) { executor in
      try await withOperationScheduler(executor) {
        let listener = try await TCPListener.bind(to: Self.loopback)
        let address = try listener.localAddress
        let request = Array("Hello over a buffer that the kernel shares".utf8)
        let response = Array("Hello back".utf8)

        try await withThrowingTaskGroup { group in
          group.addTask {
            var client = try await TCPConnection.connect(to: address)
            try await client.write { span in span.append(bytes: request) }
            #expect(try await client.readBytes() == response)
            try await client.close()
          }

          var server = try await listener.accept()
          #expect(try await server.readBytes() == request)
          try await server.write { span in span.append(bytes: response) }
          try await server.close()
          try await group.waitForAll()
        }
        try await listener.close()
      }
    }
  }

  @Test(
    .disabled("Leasing buffers is not implemented in the executors yet"),
    arguments: PThreadIOBackend.tested,
    [1, 4]
  )
  @available(anyAppleOS 27.0, *)
  func roundTripWithBuffersFromTheExecutorOnAPool(ioBackend: PThreadIOBackend, poolSize: Int) async throws {
    try await PThreadTaskExecutor.withExecutor(name: "TCPSocketTest", poolSize: poolSize, ioBackend: ioBackend) {
      executor in
      try await withTaskExecutorPreference(executor) {
        let listener = try await TCPListener.bind(to: Self.loopback)
        let address = try listener.localAddress
        let payload = (0..<100_000).map { UInt8(truncatingIfNeeded: $0 &* 7) }

        try await withThrowingTaskGroup { group in
          group.addTask {
            var client = try await TCPConnection.connect(to: address)
            try await client.writeAll(payload)
            try await client.shutdown(.write)
            try await client.close()
          }

          var server = try await listener.accept()
          #expect(try await server.readLeasedUntilEndOfStream() == payload)
          try await server.close()
          try await group.waitForAll()
        }
        try await listener.close()
      }
    }
  }

  @Test(
    .disabled("Leasing buffers is not implemented in the executors yet"),
    arguments: PThreadIOBackend.tested
  )
  @available(anyAppleOS 27.0, *)
  func theSpansOfALeaseCoverItsBytes(ioBackend: PThreadIOBackend) async throws {
    try await PThreadExecutor.withExecutor(name: "TCPSocketTest", ioBackend: ioBackend) { executor in
      try await withOperationScheduler(executor) {
        try await Self.withConnectedPair { client, server in
          try await client.write { span in span.append(bytes: [1, 2, 3, 4]) }
          var buffer = try await server.read()
          #expect(buffer.count == 4)
          #expect(buffer.bytes.byteCount == 4)
          // The memory is ours to modify while we hold the lease.
          do {
            var mutable = buffer.mutableBytes
            mutable.storeBytes(of: 9, toByteOffset: 0, as: UInt8.self)
          }
          let first = unsafe buffer.bytes.unsafeLoad(fromByteOffset: 0, as: UInt8.self)
          let last = unsafe buffer.bytes.unsafeLoad(fromByteOffset: 3, as: UInt8.self)
          #expect(first == 9)
          #expect(last == 4)
          buffer.return()
        }
      }
    }
  }

  @Test(
    .disabled("Leasing buffers is not implemented in the executors yet"),
    arguments: PThreadIOBackend.tested
  )
  @available(anyAppleOS 27.0, *)
  func aSchedulerWithoutProvidedBuffersFallsBackToTemporaryBuffers(ioBackend: PThreadIOBackend) async throws {
    try await PThreadExecutor.withExecutor(name: "TCPSocketTest", ioBackend: ioBackend) { executor in
      // The wrapper only forwards the requirements of the protocol, so the closure based operations use the
      // defaults of the protocol.
      let scheduler = ForwardingTCPScheduler(executor: executor)
      try await withOperationScheduler(scheduler) {
        let listener = try await TCPListener.bind(to: Self.loopback)
        let address = try listener.localAddress
        let payload = Array("Served by the default implementation".utf8)

        try await withThrowingTaskGroup { group in
          group.addTask {
            var client = try await TCPConnection.connect(to: address)
            try await client.write { span in span.append(bytes: payload) }
            try await client.shutdown(.write)
            try await client.close()
          }

          var server = try await listener.accept()
          #expect(try await server.readLeasedUntilEndOfStream() == payload)
          try await server.close()
          try await group.waitForAll()
        }
        try await listener.close()

        // The leased buffers of the defaults are allocated, and returning them frees them.
        let defaultsListener = try await TCPListener.bind(to: Self.loopback)
        var sender = try await TCPConnection.connect(to: defaultsListener.localAddress)
        var receiver = try await defaultsListener.accept()
        try await defaultsListener.close()
        try await sender.write { span in span.append(bytes: [5, 6, 7]) }
        let received = try await receiver.read()
        #expect(received.count == 3)
        received.return()
        try await sender.close()
        try await receiver.close()
      }
    }
  }

  /// Runs the body with a connected client and server, which are closed afterwards.
  @available(anyAppleOS 27.0, *)
  private static func withConnectedPair<Return>(
    _ body: (inout TCPConnection, inout TCPConnection) async throws -> Return
  ) async throws -> Return {
    let listener = try await TCPListener.bind(to: Self.loopback)
    let address = try listener.localAddress
    var client = try await TCPConnection.connect(to: address)
    var server = try await listener.accept()
    try await listener.close()
    let result: Result<Return, any Error>
    do {
      result = .success(try await body(&client, &server))
    } catch {
      result = .failure(error)
    }
    try await client.close()
    try await server.close()
    return try result.get()
  }
}

@available(anyAppleOS 27.0, *)
extension TCPConnection {
  /// Reads once, returning at most `count` bytes, or none at the end of the stream.
  fileprivate mutating func read(count: Int) async throws(IOError) -> [UInt8] {
    // The buffer has to stay alive while the read is in flight so we heap alloc here.
    let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: count, alignment: 1)
    defer {
      unsafe buffer.deallocate()
    }

    var output = unsafe OutputRawSpan(buffer: buffer, initializedCount: 0)
    let received = try await self.read(into: &output)
    _ = unsafe output.finalize(for: buffer)
    return unsafe Array(UnsafeRawBufferPointer(rebasing: buffer[..<received]))
  }

  /// Reads until the peer closed its side of the connection.
  fileprivate mutating func readUntilEndOfStream() async throws(IOError) -> [UInt8] {
    // The buffer has to stay alive while the read is in flight so we heap alloc here.
    let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 1024, alignment: 1)
    defer {
      unsafe buffer.deallocate()
    }

    var received = [UInt8]()
    while true {
      var output = unsafe OutputRawSpan(buffer: buffer, initializedCount: 0)
      let count = try await self.read(into: &output)
      let initializedCount = unsafe output.finalize(for: buffer)
      #expect(initializedCount == count)

      if count == 0 {
        return received
      }
      unsafe received += UnsafeRawBufferPointer(rebasing: buffer[..<count])
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
      unsafe buffer.deallocate()
    }

    while true {
      var output = unsafe OutputRawSpan(buffer: buffer, initializedCount: 0)
      let count = try await self.read(into: &output)
      _ = unsafe output.finalize(for: buffer)
      if count == 0 {
        return
      }
      try await unsafe self.write(from: RawSpan(_unsafeBytes: UnsafeRawBufferPointer(rebasing: buffer[..<count])))
    }
  }
}

@available(anyAppleOS 27.0, *)
extension TCPConnection.ReadHalf {
  /// Reads until the peer closed its side of the connection.
  fileprivate mutating func readUntilEndOfStream() async throws(IOError) -> [UInt8] {
    // The buffer has to stay alive while the read is in flight so we heap alloc here.
    let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 64 * 1024, alignment: 1)
    defer {
      unsafe buffer.deallocate()
    }

    var received = [UInt8]()
    while true {
      var output = unsafe OutputRawSpan(buffer: buffer, initializedCount: 0)
      let count = try await self.read(into: &output)
      _ = unsafe output.finalize(for: buffer)
      if count == 0 {
        return received
      }
      unsafe received += UnsafeRawBufferPointer(rebasing: buffer[..<count])
    }
  }
}

@available(anyAppleOS 27.0, *)
extension TCPConnection {
  /// Reads once with a buffer that the platform provides.
  fileprivate mutating func readBytes() async throws(IOError) -> [UInt8] {
    try await self.read { span in span.bytesArray() }
  }

  /// Writes all bytes, in as many writes with buffers that the platform provides as it takes.
  fileprivate mutating func writeAll(_ bytes: [UInt8]) async throws(IOError) {
    var offset = 0
    while offset < bytes.count {
      offset += try await self.write { span in
        let count = min(span.freeCapacity, bytes.count - offset)
        span.append(bytes: Array(bytes[offset..<(offset + count)]))
        return count
      }
    }
  }

  /// Reads with buffers that the platform provides until the peer closed its side of the connection.
  fileprivate mutating func readLeasedUntilEndOfStream() async throws(IOError) -> [UInt8] {
    var contents = [UInt8]()
    while true {
      let piece = try await self.readBytes()
      if piece.isEmpty {
        return contents
      }
      contents += piece
    }
  }
}

/// A scheduler for TCP sockets that forwards every operation to an executor, and leaves the closure based
/// operations to the defaults of the protocol.
@available(anyAppleOS 27.0, *)
private final class ForwardingTCPScheduler: TCPSocketOperationScheduler {
  typealias TCPConnection = PThreadExecutor.TCPConnection
  typealias TCPListener = PThreadExecutor.TCPListener

  let executor: PThreadExecutor

  init(executor: PThreadExecutor) {
    self.executor = executor
  }

  func connect(to address: SocketAddress) async throws(IOError) -> TCPConnection {
    try await self.executor.connect(to: address)
  }

  func listen(on address: SocketAddress, backlog: Int) async throws(IOError) -> TCPListener {
    try await self.executor.listen(on: address, backlog: backlog)
  }

  func accept(listener: borrowing TCPListener) async throws(IOError) -> TCPConnection {
    try await self.executor.accept(listener: listener)
  }

  func read(connection: borrowing TCPConnection, into buffer: inout OutputRawSpan) async throws(IOError) -> Int {
    try await self.executor.read(connection: connection, into: &buffer)
  }

  func write(connection: borrowing TCPConnection, from buffer: RawSpan) async throws(IOError) -> Int {
    try await self.executor.write(connection: connection, from: buffer)
  }

  func leaseBuffer() -> LeasedBuffer {
    self.executor.leaseBuffer()
  }

  func read(connection: borrowing TCPConnection) async throws(IOError) -> LeasedBuffer {
    try await self.executor.read(connection: connection)
  }

  func shutdown(connection: borrowing TCPConnection, direction: SocketShutdownDirection) async throws(IOError) {
    try await self.executor.shutdown(connection: connection, direction: direction)
  }

  func close(connection: consuming TCPConnection) async throws(IOError) {
    try await self.executor.close(connection: connection)
  }

  func close(listener: consuming TCPListener) async throws(IOError) {
    try await self.executor.close(listener: listener)
  }

  func localAddress(of connection: borrowing TCPConnection) throws(IOError) -> SocketAddress {
    try self.executor.localAddress(of: connection)
  }

  func localAddress(of listener: borrowing TCPListener) throws(IOError) -> SocketAddress {
    try self.executor.localAddress(of: listener)
  }
}
#endif
#endif
