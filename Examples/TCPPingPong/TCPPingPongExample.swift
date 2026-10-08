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

/// Sends TCP ping pong between a client and a server over the loopback interface.
@main
@available(anyAppleOS 27.0, *)
struct TCPPingPongExample {
  /// The number of iterations.
  static let rounds = 5

  /// The time that each side waits before sending its next message.
  static let pause = Duration.milliseconds(200)

  static func main() async throws {
    try await PThreadExecutor.withExecutor(name: "TCPPingPong") { executor in
      try await withOperationScheduler(executor) {
        let listener = try await TCPListener.bind(
          to: .v4(SocketAddress.V4(address: .loopback, port: 0))
        )
        let address = try listener.localAddress
        print("Server listening on port \(address.port)")

        try await withThrowingTaskGroup { group in
          group.addTask(name: "Client") {
            try await Self.client(connectingTo: address)
          }

          var connection = try await listener.accept()
          print("Server accepted a connection")
          try await Self.server(on: &connection)
          try await connection.close()

          try await group.waitForAll()
        }

        try await listener.close()
        print("Done")
      }
    }
  }

  /// Connects to the server and sends a ping for every round, waiting for the pong before the next one.
  private static func client(connectingTo address: SocketAddress) async throws {
    var connection = try await TCPConnection.connect(to: address)
    print("Client connected from port \(try connection.localAddress.port)")

    for round in 1...Self.rounds {
      let ping = "ping \(round)"
      try await connection.write(message: ping)
      print("Client sent     '\(ping)'")

      let pong = try await connection.read(messageLength: ping.utf8.count)
      print("Client received '\(pong)'")

      try await Task.sleep(for: Self.pause)
    }

    try await connection.close()
  }

  /// Answers every ping of the client with a pong.
  private static func server(on connection: inout TCPConnection) async throws {
    for round in 1...Self.rounds {
      let ping = try await connection.read(messageLength: "ping \(round)".utf8.count)
      print("Server received '\(ping)'")

      try await Task.sleep(for: Self.pause)

      let pong = "pong \(round)"
      try await connection.write(message: pong)
      print("Server sent     '\(pong)'")
    }
  }
}

@available(anyAppleOS 27.0, *)
extension TCPConnection {
  fileprivate mutating func write(message: String) async throws(IOError) {
    try await self.write(from: message.utf8Span.span.bytes)
  }

  fileprivate mutating func read(messageLength: Int) async throws -> String {
    // TODO: We need async OutputSpan overloads on Array/String to avoid this
    let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: messageLength, alignment: 1)
    defer {
      buffer.deallocate()
    }

    var output = OutputRawSpan(buffer: buffer, initializedCount: 0)
    while output.freeCapacity > 0 {
      if try await self.read(into: &output) == 0 {
        throw EndOfStreamError()
      }
    }
    let count = output.finalize(for: buffer)
    return String(decoding: UnsafeRawBufferPointer(rebasing: buffer[..<count]), as: UTF8.self)
  }
}

/// The peer closed the connection before a message was complete.
struct EndOfStreamError: Error {}
#else
@main
struct IOExample {
  static func main() {
    print("The I/O example requires the ExperimentalIO trait on Linux, FreeBSD or Darwin.")
  }
}
#endif
