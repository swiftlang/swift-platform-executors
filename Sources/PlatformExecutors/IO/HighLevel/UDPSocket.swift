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
/// A UDP socket.
///
/// A socket sends and receives datagrams to and from any peer. It is created by binding it to a local
/// address with ``bind(to:)``.
///
/// A socket uniquely owns the underlying platform resource, so it cannot be copied. It must be closed
/// explicitly with ``close()`` since closing is an asynchronous operation, and destroying a socket without
/// closing it traps.
///
/// ```swift
/// var socket = try await UDPSocket.bind(to: address)
/// let (count, sender) = try await socket.receive(into: &datagram)
/// try await socket.send(from: reply, to: sender)
/// try await socket.close()
/// ```
@available(anyAppleOS 27.0, *)
public struct UDPSocket: ~Copyable, Sendable {
  /// The scheduler that services the socket.
  private let scheduler: any UDPSocketOperationScheduler

  /// The scheduler's handle of the socket, or `nil` once the socket is closed.
  private var socket: (any Sendable)?

  private init<Scheduler: UDPSocketOperationScheduler>(
    scheduler: Scheduler,
    socket: Scheduler.UDPSocket
  ) {
    self.scheduler = scheduler
    self.socket = socket
  }

  /// Creates a new socket and binds it to the given address.
  ///
  /// - Parameter address: The address to bind to. Binding to port zero lets the platform pick a free port,
  ///   which ``localAddress`` reports afterwards.
  /// - Returns: The bound socket.
  public static func bind(to address: SocketAddress) async throws(IOError) -> UDPSocket {
    guard
      let scheduler = OperationSchedulerPreference.resolve(as: (any UDPSocketOperationScheduler).self)
    else {
      fatalError(
        "No operation scheduler for UDP sockets found. Use withOperationScheduler or a task executor preference."
      )
    }
    return try await Self.bind(to: address, on: scheduler)
  }

  private static func bind<Scheduler: UDPSocketOperationScheduler>(
    to address: SocketAddress,
    on scheduler: Scheduler
  ) async throws(IOError) -> UDPSocket {
    let socket = try await scheduler.bind(to: address)
    return UDPSocket(scheduler: scheduler, socket: socket)
  }

  /// The address that the socket is bound to.
  public var localAddress: SocketAddress {
    get throws(IOError) {
      try self.localAddress(on: self.scheduler)
    }
  }

  private func localAddress<Scheduler: UDPSocketOperationScheduler>(
    on scheduler: Scheduler
  ) throws(IOError) -> SocketAddress {
    try scheduler.localAddress(of: self.socket(of: scheduler))
  }

  /// Receives one datagram into the free capacity of the given buffer.
  ///
  /// The bytes are appended to the buffer. A datagram that is larger than the free capacity of the buffer is
  /// truncated, and its remaining bytes are discarded.
  ///
  /// - Parameter buffer: The buffer to receive into.
  /// - Returns: The number of bytes received and the address of the sender.
  @discardableResult
  public mutating func receive(
    into buffer: inout OutputRawSpan
  ) async throws(IOError) -> (count: Int, sender: SocketAddress) {
    try await self.receive(into: &buffer, on: self.scheduler)
  }

  private func receive<Scheduler: UDPSocketOperationScheduler>(
    into buffer: inout OutputRawSpan,
    on scheduler: Scheduler
  ) async throws(IOError) -> (count: Int, sender: SocketAddress) {
    try await scheduler.receive(socket: self.socket(of: scheduler), into: &buffer)
  }

  /// Sends the bytes of the given buffer as one datagram to the given address.
  ///
  /// - Parameters:
  ///   - buffer: The bytes of the datagram.
  ///   - address: The address to send the datagram to.
  public mutating func send(
    from buffer: RawSpan,
    to address: SocketAddress
  ) async throws(IOError) {
    try await self.send(from: buffer, to: address, on: self.scheduler)
  }

  private func send<Scheduler: UDPSocketOperationScheduler>(
    from buffer: RawSpan,
    to address: SocketAddress,
    on scheduler: Scheduler
  ) async throws(IOError) {
    // A datagram is sent as a whole or not at all.
    _ = try await scheduler.send(socket: self.socket(of: scheduler), from: buffer, to: address)
  }

  /// Closes the socket.
  public consuming func close() async throws(IOError) {
    try await Self.close(self.socket.take(), on: self.scheduler)
  }

  private static func close<Scheduler: UDPSocketOperationScheduler>(
    _ socket: (any Sendable)?,
    on scheduler: Scheduler
  ) async throws(IOError) {
    let socket = socket as! Scheduler.UDPSocket
    try await withTaskCancellationShield { () async throws(IOError) -> Void in
      try await scheduler.close(socket: socket)
    }
  }

  /// Returns the handle of the socket as the handle type of the given scheduler.
  ///
  /// - Parameter scheduler: The scheduler that services the socket.
  private func socket<Scheduler: UDPSocketOperationScheduler>(
    of scheduler: Scheduler
  ) -> Scheduler.UDPSocket {
    // The handle was created by this scheduler, and it is only `nil` once
    // the socket is closed, which consumes it. So the cast cannot fail.
    self.socket as! Scheduler.UDPSocket
  }

  deinit {
    if self.socket != nil {
      fatalError("A UDPSocket was destroyed without being closed.")
    }
  }
}
#endif
