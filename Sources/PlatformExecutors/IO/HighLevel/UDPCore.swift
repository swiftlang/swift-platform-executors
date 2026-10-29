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
/// What ``UDPSocket`` and ``UDPConnection`` share.
@available(anyAppleOS 27.0, *)
struct UDPCore: ~Copyable, Sendable {
  /// The scheduler that services the socket.
  let scheduler: any UDPSocketOperationScheduler

  /// The scheduler's handle of the socket, or `nil` once the socket is closed.
  var socket: (any Sendable)?

  init(scheduler: any UDPSocketOperationScheduler, socket: (any Sendable)?) {
    self.scheduler = scheduler
    self.socket = socket
  }

  private init<Scheduler: UDPSocketOperationScheduler>(
    scheduler: Scheduler,
    socket: Scheduler.UDPSocket
  ) {
    self.scheduler = scheduler
    self.socket = socket
  }

  /// Resolves the scheduler that services new sockets.
  private static func resolveScheduler() -> any UDPSocketOperationScheduler {
    guard
      let scheduler = OperationSchedulerPreference.resolve(as: (any UDPSocketOperationScheduler).self)
    else {
      fatalError(
        "No operation scheduler for UDP sockets found. Use withOperationScheduler or a task executor preference."
      )
    }
    return scheduler
  }

  // MARK: - Creating

  static func bind(to address: SocketAddress) async throws(IOError) -> UDPCore {
    try await Self.bind(to: address, on: Self.resolveScheduler())
  }

  private static func bind<Scheduler: UDPSocketOperationScheduler>(
    to address: SocketAddress,
    on scheduler: Scheduler
  ) async throws(IOError) -> UDPCore {
    UDPCore(scheduler: scheduler, socket: try await scheduler.bind(to: address))
  }

  static func connect(to address: SocketAddress) async throws(IOError) -> UDPCore {
    try await Self.connect(to: address, on: Self.resolveScheduler())
  }

  private static func connect<Scheduler: UDPSocketOperationScheduler>(
    to address: SocketAddress,
    on scheduler: Scheduler
  ) async throws(IOError) -> UDPCore {
    UDPCore(scheduler: scheduler, socket: try await scheduler.connectUDP(to: address))
  }

  /// Connects the socket to the given address, and closes it if that fails.
  consuming func connected(to address: SocketAddress) async throws(IOError) -> UDPCore {
    let scheduler = self.scheduler
    let socket = self.socket.take()
    do {
      try await Self.connect(socket, to: address, on: scheduler)
    } catch {
      try? await Self.close(socket, on: scheduler)
      throw error
    }
    return UDPCore(scheduler: scheduler, socket: socket)
  }

  private static func connect<Scheduler: UDPSocketOperationScheduler>(
    _ socket: (any Sendable)?,
    to address: SocketAddress,
    on scheduler: Scheduler
  ) async throws(IOError) {
    try await scheduler.connectUDP(socket: Self.socket(socket, of: scheduler), to: address)
  }

  // MARK: - Addresses

  var localAddress: SocketAddress {
    get throws(IOError) {
      try Self.localAddress(socket: self.socket, on: self.scheduler)
    }
  }

  private static func localAddress<Scheduler: UDPSocketOperationScheduler>(
    socket: (any Sendable)?,
    on scheduler: Scheduler
  ) throws(IOError) -> SocketAddress {
    try scheduler.localAddress(of: Self.socket(socket, of: scheduler))
  }

  var remoteAddress: SocketAddress {
    get throws(IOError) {
      try Self.remoteAddress(socket: self.socket, on: self.scheduler)
    }
  }

  private static func remoteAddress<Scheduler: UDPSocketOperationScheduler>(
    socket: (any Sendable)?,
    on scheduler: Scheduler
  ) throws(IOError) -> SocketAddress {
    try scheduler.remoteAddress(of: Self.socket(socket, of: scheduler))
  }

  // MARK: - Datagrams

  static func receive<Scheduler: UDPSocketOperationScheduler>(
    into buffer: inout OutputRawSpan,
    socket: (any Sendable)?,
    on scheduler: Scheduler
  ) async throws(IOError) -> (count: Int, sender: SocketAddress) {
    try await scheduler.receive(socket: Self.socket(socket, of: scheduler), into: &buffer)
  }

  static func send<Scheduler: UDPSocketOperationScheduler>(
    from buffer: RawSpan,
    to address: SocketAddress,
    socket: (any Sendable)?,
    on scheduler: Scheduler
  ) async throws(IOError) {
    // A datagram is sent as a whole or not at all.
    _ = try await scheduler.send(socket: Self.socket(socket, of: scheduler), from: buffer, to: address)
  }

  static func read<Scheduler: UDPSocketOperationScheduler>(
    into buffer: inout OutputRawSpan,
    socket: (any Sendable)?,
    on scheduler: Scheduler
  ) async throws(IOError) -> Int {
    try await scheduler.read(socket: Self.socket(socket, of: scheduler), into: &buffer)
  }

  static func write<Scheduler: UDPSocketOperationScheduler>(
    from buffer: RawSpan,
    socket: (any Sendable)?,
    on scheduler: Scheduler
  ) async throws(IOError) {
    // A datagram is sent as a whole or not at all.
    _ = try await scheduler.write(socket: Self.socket(socket, of: scheduler), from: buffer)
  }

  static func receive<Scheduler: UDPSocketOperationScheduler, Return: ~Copyable>(
    socket: (any Sendable)?,
    on scheduler: Scheduler,
    _ body: (inout OutputRawSpan, SocketAddress) -> Return
  ) async throws(IOError) -> Return {
    try await scheduler.receive(socket: Self.socket(socket, of: scheduler), body: body)
  }

  static func send<Scheduler: UDPSocketOperationScheduler, Return: ~Copyable>(
    to address: SocketAddress,
    socket: (any Sendable)?,
    on scheduler: Scheduler,
    _ body: (inout OutputRawSpan) -> Return
  ) async throws(IOError) -> Return {
    try await scheduler.send(socket: Self.socket(socket, of: scheduler), to: address, body: body)
  }

  static func read<Scheduler: UDPSocketOperationScheduler, Return: ~Copyable>(
    socket: (any Sendable)?,
    on scheduler: Scheduler,
    _ body: (inout OutputRawSpan) -> Return
  ) async throws(IOError) -> Return {
    try await scheduler.read(socket: Self.socket(socket, of: scheduler), body: body)
  }

  static func write<Scheduler: UDPSocketOperationScheduler, Return: ~Copyable>(
    socket: (any Sendable)?,
    on scheduler: Scheduler,
    _ body: (inout OutputRawSpan) -> Return
  ) async throws(IOError) -> Return {
    try await scheduler.write(socket: Self.socket(socket, of: scheduler), body: body)
  }

  static func receive<Scheduler: UDPSocketOperationScheduler>(
    socket: (any Sendable)?,
    on scheduler: Scheduler
  ) async throws(IOError) -> ReceivedDatagram {
    try await scheduler.receive(socket: Self.socket(socket, of: scheduler))
  }

  static func read<Scheduler: UDPSocketOperationScheduler>(
    socket: (any Sendable)?,
    on scheduler: Scheduler
  ) async throws(IOError) -> LeasedBuffer {
    try await scheduler.read(socket: Self.socket(socket, of: scheduler))
  }

  // MARK: - Closing

  consuming func close() async throws(IOError) {
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
  /// - Parameters:
  ///   - socket: The erased handle of the socket.
  ///   - scheduler: The scheduler that services the socket.
  private static func socket<Scheduler: UDPSocketOperationScheduler>(
    _ socket: (any Sendable)?,
    of scheduler: Scheduler
  ) -> Scheduler.UDPSocket {
    // The handle was created by this scheduler, and it is only `nil` once
    // the socket is closed, which consumes it. So the cast cannot fail.
    socket as! Scheduler.UDPSocket
  }

  deinit {
    if self.socket != nil {
      fatalError("A UDP socket was destroyed without being closed.")
    }
  }
}
#endif
