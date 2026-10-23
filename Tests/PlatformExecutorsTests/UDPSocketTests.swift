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

import BasicContainers
import Testing
@_spi(ExperimentalScheduling) @_spi(ConcurrencyExecutors) @_spi(ExperimentalCustomExecutors) import _Concurrency
@_spi(ExperimentalScheduling) @_spi(ConcurrencyExecutors) @_spi(ExperimentalCustomExecutors) import PlatformExecutors

@Suite
struct UDPSocketTests {
  @available(anyAppleOS 27.0, *)
  private static let loopback = SocketAddress.v4(SocketAddress.V4(address: .loopback, port: 0))

  @Test(arguments: PThreadIOBackend.tested)
  @available(anyAppleOS 27.0, *)
  func bindReportsThePickedPort(ioBackend: PThreadIOBackend) async throws {
    try await PThreadExecutor.withExecutor(name: "UDPSocketTest", ioBackend: ioBackend) { executor in
      try await withOperationScheduler(executor) {
        let socket = try await UDPSocket.bind(to: Self.loopback)
        let address = try socket.localAddress
        try await socket.close()

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
  func exchangeWithOperationScheduler(ioBackend: PThreadIOBackend) async throws {
    try await PThreadExecutor.withExecutor(name: "UDPSocketTest", ioBackend: ioBackend) { executor in
      try await withOperationScheduler(executor) {
        try await Self.exchange()
      }
    }
  }

  @Test(arguments: PThreadIOBackend.tested, [1, 4])
  @available(anyAppleOS 27.0, *)
  func exchangeWithPThreadTaskExecutorPreference(ioBackend: PThreadIOBackend, poolSize: Int) async throws {
    try await PThreadTaskExecutor.withExecutor(name: "UDPSocketTest", poolSize: poolSize, ioBackend: ioBackend) {
      executor in
      try await withTaskExecutorPreference(executor) {
        try await Self.exchange()
      }
    }
  }

  @Test(arguments: PThreadIOBackend.tested)
  @available(anyAppleOS 27.0, *)
  func receiveTruncatesALargerDatagram(ioBackend: PThreadIOBackend) async throws {
    try await PThreadExecutor.withExecutor(name: "UDPSocketTest", ioBackend: ioBackend) { executor in
      try await withOperationScheduler(executor) {
        var receiver = try await UDPSocket.bind(to: Self.loopback)
        var sender = try await UDPSocket.bind(to: Self.loopback)

        let payload = Array("0123456789".utf8)
        try await sender.send(payload, to: receiver.localAddress)
        let (datagram, _) = try await receiver.receive(maxCount: 4)
        #expect(datagram == Array("0123".utf8))

        try await sender.close()
        try await receiver.close()
      }
    }
  }

  @Test(arguments: PThreadIOBackend.tested, [1, 4])
  @available(anyAppleOS 27.0, *)
  func cancellingAPendingReceiveResumesWithCancelledAndKeepsTheSocket(
    ioBackend: PThreadIOBackend,
    poolSize: Int
  ) async throws {
    try await PThreadTaskExecutor.withExecutor(name: "UDPSocketTest", poolSize: poolSize, ioBackend: ioBackend) {
      executor in
      try await withTaskExecutorPreference(executor) {
        let payload = Array("Sent after the receive was cancelled".utf8)
        let (cancelled, cancelledContinuation) = AsyncStream.makeStream(of: Void.self)
        let (ready, readyContinuation) = AsyncStream.makeStream(of: Void.self)

        try await withThrowingTaskGroup { group in
          // A noncopyable value cannot be consumed out of a closure capture, so the
          // socket is moved into the child task through an optional.
          let bound = try await UDPSocket.bind(to: Self.loopback)
          let address = try bound.localAddress
          var receiverBox: UDPSocket? = bound
          group.addTask {
            var receiver = receiverBox.take()!
            readyContinuation.yield()

            // Nothing was sent yet, so the receive waits until the task is cancelled.
            let error = await #expect(throws: IOError.self) {
              _ = try await receiver.receive(maxCount: 1024)
            }
            #expect(error?.code == .cancelled)
            cancelledContinuation.yield()

            // The socket is still usable after the cancelled receive.
            let (datagram, _) = try await withTaskCancellationShield { () async throws(IOError) in
              try await receiver.receive(maxCount: 1024)
            }
            #expect(datagram == payload)
            try await receiver.close()
          }

          for await _ in ready {
            break
          }
          group.cancelAll()
          for await _ in cancelled {
            break
          }

          var sender = try await UDPSocket.bind(to: Self.loopback)
          try await sender.send(payload, to: address)
          try await sender.close()
          try await group.waitForAll()
        }
      }
    }
  }

  /// Sends a datagram to a socket, which sends a reply to the address it received the datagram from.
  @available(anyAppleOS 27.0, *)
  private static func exchange() async throws {
    var server = try await UDPSocket.bind(to: Self.loopback)
    var client = try await UDPSocket.bind(to: Self.loopback)
    let serverAddress = try server.localAddress
    let clientAddress = try client.localAddress

    try await client.send(Array("ping".utf8), to: serverAddress)
    let (request, requestSender) = try await server.receive(maxCount: 1024)
    #expect(request == Array("ping".utf8))
    #expect(requestSender == clientAddress)

    try await server.send(Array("pong".utf8), to: requestSender)
    let (reply, replySender) = try await client.receive(maxCount: 1024)
    #expect(reply == Array("pong".utf8))
    #expect(replySender == serverAddress)

    try await client.close()
    try await server.close()
  }
}

@available(anyAppleOS 27.0, *)
extension UDPSocket {
  /// Receives one datagram of at most `maxCount` bytes.
  fileprivate mutating func receive(maxCount: Int) async throws(IOError) -> ([UInt8], SocketAddress) {
    var buffer = UniqueArray<UInt8>(minimumCapacity: maxCount)
    let (_, sender) = try await buffer.append(addingByteCount: maxCount) {
      (output: inout OutputRawSpan) async throws(IOError) -> (count: Int, sender: SocketAddress) in
      try await self.receive(into: &output)
    }
    return ((0..<buffer.count).map { buffer[$0] }, sender)
  }

  /// Sends the bytes as one datagram.
  fileprivate mutating func send(_ bytes: [UInt8], to address: SocketAddress) async throws(IOError) {
    try await self.send(from: bytes.span.bytes, to: address)
  }
}
#endif
#endif
