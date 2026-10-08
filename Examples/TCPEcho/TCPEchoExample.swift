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

/// Echoes messages between a client and a server over the loopback interface.
@main
@available(anyAppleOS 27.0, *)
struct TCPEchoExample {
  /// The messages that the client sends.
  static let messages = ["Hello", "from", "the", "TCP", "echo", "example"]

  /// The time that the client waits before sending its next message.
  static let pause = Duration.milliseconds(200)

  static func main() async throws {
    try await PThreadExecutor.withExecutor(name: "TCPEcho") { executor in
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

  /// Connects to the server, and sends the messages while concurrently printing the echoes.
  private static func client(connectingTo address: SocketAddress) async throws {
    let connection = try await TCPConnection.connect(to: address)
    print("Client connected from port \(try connection.localAddress.port)")

    try await connection.withSplit { readHalf, writeHalf in
      _ = try await withConcurrently {
        try await Self.printEchoes(from: readHalf)
      } _: {
        for message in Self.messages {
          try await writeHalf.write(from: Array(message.utf8).span.bytes)
          print("Client sent     '\(message)'")
          try await Task.sleep(for: Self.pause)
        }
        // Closing our side of the connection lets the server finish echoing.
        try await writeHalf.shutdown()
      }
    }

    try await connection.close()
  }

  /// Prints the echoes until the server closed its side of the connection.
  private static func printEchoes(from readHalf: borrowing TCPConnection.ReadHalf) async throws {
    // The buffer has to stay alive while a read is in flight so we heap alloc here.
    let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 1024, alignment: 1)
    defer {
      buffer.deallocate()
    }

    while true {
      var output = OutputRawSpan(buffer: buffer, initializedCount: 0)
      let count = try await readHalf.read(into: &output)
      _ = output.finalize(for: buffer)
      if count == 0 {
        return
      }
      let echo = String(decoding: UnsafeRawBufferPointer(rebasing: buffer[..<count]), as: UTF8.self)
      print("Client received '\(echo)'")
    }
  }

  /// Writes everything back that the client sends until the client closes its side of the connection.
  private static func server(on connection: inout TCPConnection) async throws {
    // The buffer has to stay alive while a read is in flight so we heap alloc here.
    let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 1024, alignment: 1)
    defer {
      buffer.deallocate()
    }

    while true {
      var output = OutputRawSpan(buffer: buffer, initializedCount: 0)
      let count = try await connection.read(into: &output)
      _ = output.finalize(for: buffer)
      if count == 0 {
        return
      }
      try await connection.write(from: RawSpan(_unsafeBytes: UnsafeRawBufferPointer(rebasing: buffer[..<count])))
    }
  }
}
#else
@main
struct TCPEchoExample {
  static func main() {
    print("The TCP echo example requires the ExperimentalIO trait on Linux, FreeBSD or Darwin.")
  }
}
#endif
