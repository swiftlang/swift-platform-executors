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
/// A TCP socket that listens for incoming connections.
///
/// A listener uniquely owns the underlying platform resource, so it cannot be copied. It must be closed
/// explicitly with ``close()`` since closing is an asynchronous operation, and destroying a listener without
/// closing it traps.
///
/// ```swift
/// let listener = try await TCPListener.bind(to: address)
/// while true {
///   var socket = try await listener.accept()
///   ...
///   try await socket.close()
/// }
/// try await listener.close()
/// ```
@available(anyAppleOS 27.0, *)
public struct TCPListener: ~Copyable, Sendable {
  /// The scheduler that services the listener and the sockets it accepts.
  private let scheduler: any TCPSocketOperationScheduler

  /// The scheduler's handle of the listener, or `nil` once the listener is closed.
  private var listener: (any Sendable)?

  private init<Scheduler: TCPSocketOperationScheduler>(
    scheduler: Scheduler,
    listener: Scheduler.TCPListener
  ) {
    self.scheduler = scheduler
    self.listener = listener
  }

  /// Creates a new socket, binds it to the given address and starts listening for incoming connections.
  ///
  /// - Parameters:
  ///   - address: The address to bind to. Binding to port zero lets the platform pick a free port, which
  ///     ``localAddress`` reports afterwards.
  ///   - backlog: The maximum number of connections the platform queues up before refusing new ones.
  /// - Returns: The listening socket.
  public static func bind(
    to address: SocketAddress,
    backlog: Int = 1024
  ) async throws(IOError) -> TCPListener {
    guard
      let scheduler = OperationSchedulerPreference.resolve({ $0 as? any TCPSocketOperationScheduler })
    else {
      fatalError(
        "No operation scheduler for TCP sockets found."
      )
    }
    return try await Self.bind(to: address, backlog: backlog, on: scheduler)
  }

  private static func bind<Scheduler: TCPSocketOperationScheduler>(
    to address: SocketAddress,
    backlog: Int,
    on scheduler: Scheduler
  ) async throws(IOError) -> TCPListener {
    let listener = try await withOperation(on: scheduler, of: Scheduler.TCPListener.self) {
      continuation,
      state in
      scheduler.submitListen(continuation, state: &state, on: address, backlog: backlog)
    }
    return TCPListener(scheduler: scheduler, listener: listener)
  }

  /// The address that the listener is bound to.
  public var localAddress: SocketAddress {
    get throws(IOError) {
      try self.localAddress(on: self.scheduler)
    }
  }

  private func localAddress<Scheduler: TCPSocketOperationScheduler>(
    on scheduler: Scheduler
  ) throws(IOError) -> SocketAddress {
    try scheduler.localAddress(of: self.listener(of: scheduler))
  }

  /// Accepts the next incoming connection.
  ///
  /// - Returns: The socket of the accepted connection.
  public func accept() async throws(IOError) -> TCPConnection {
    try await self.accept(on: self.scheduler)
  }

  private func accept<Scheduler: TCPSocketOperationScheduler>(
    on scheduler: Scheduler
  ) async throws(IOError) -> TCPConnection {
    let listener = self.listener(of: scheduler)
    let connection = try await withOperation(on: scheduler, of: Scheduler.TCPConnection.self) {
      continuation,
      state in
      scheduler.submitAccept(continuation, state: &state, listener: listener)
    }
    return TCPConnection(scheduler: scheduler, connection: connection)
  }

  /// Closes the listener.
  public consuming func close() async throws(IOError) {
    try await Self.close(self.listener.take(), on: self.scheduler)
  }

  private static func close<Scheduler: TCPSocketOperationScheduler>(
    _ listener: (any Sendable)?,
    on scheduler: Scheduler
  ) async throws(IOError) {
    let listener = listener as! Scheduler.TCPListener
    try await withTaskCancellationShield { () async throws(IOError) -> Void in
      try await withOperation(on: scheduler, of: Void.self) { continuation, state in
        scheduler.submitClose(continuation, state: &state, listener: listener)
      }
    }
  }

  /// Returns the handle of the listener as the handle type of the given scheduler.
  ///
  /// - Parameter scheduler: The scheduler that services the listener.
  private func listener<Scheduler: TCPSocketOperationScheduler>(
    of scheduler: Scheduler
  ) -> Scheduler.TCPListener {
    // The handle was created by this scheduler, and it is only `nil` once
    // the listener is closed, which consumes it. So the cast cannot fail.
    self.listener as! Scheduler.TCPListener
  }

  deinit {
    if self.listener != nil {
      fatalError("A TCPListener was destroyed without being closed.")
    }
  }
}
#endif
