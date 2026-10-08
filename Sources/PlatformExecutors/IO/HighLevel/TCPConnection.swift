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
/// A connected TCP socket.
///
/// A connection is created by connecting to a listening socket with ``connect(to:)`` or by accepting one
/// with ``TCPListener/accept()``.
///
/// A connection uniquely owns the underlying platform resource, so it cannot be copied. It must be closed
/// explicitly with ``close()`` since closing is an asynchronous operation, and destroying a connection
/// without closing it traps.
///
/// ```swift
/// var connection = try await TCPConnection.connect(to: address)
/// try await connection.write(from: request.bytes)
/// let count = try await connection.read(into: &response)
/// try await connection.close()
/// ```
@available(anyAppleOS 27.0, *)
public struct TCPConnection: ~Copyable, Sendable {
  /// The scheduler that services the socket.
  private let scheduler: any TCPSocketOperationScheduler

  /// The scheduler's handle of the socket, or `nil` once the socket is closed.
  private var connection: (any Sendable)?

  init<Scheduler: TCPSocketOperationScheduler>(
    scheduler: Scheduler,
    connection: Scheduler.TCPConnection
  ) {
    self.scheduler = scheduler
    self.connection = connection
  }

  /// Creates a new socket and connects it to the given address.
  ///
  /// - Parameter address: The address to connect to.
  /// - Returns: The connected socket.
  public static func connect(
    to address: SocketAddress
  ) async throws(IOError) -> TCPConnection {
    guard
      let scheduler = OperationSchedulerPreference.resolve(as: (any TCPSocketOperationScheduler).self)
    else {
      fatalError(
        "No operation scheduler for TCP sockets found. Use withOperationScheduler or a task executor preference."
      )
    }
    return try await Self.connect(to: address, on: scheduler)
  }

  private static func connect<Scheduler: TCPSocketOperationScheduler>(
    to address: SocketAddress,
    on scheduler: Scheduler
  ) async throws(IOError) -> TCPConnection {
    let connection = try await withOperation(on: scheduler) {
      continuation,
      state in
      scheduler.submitConnect(continuation, state: &state, to: address)
    }
    return TCPConnection(scheduler: scheduler, connection: connection)
  }

  /// The address that the socket is bound to locally.
  public var localAddress: SocketAddress {
    get throws(IOError) {
      try Self.localAddress(connection: self.connection, on: self.scheduler)
    }
  }

  private static func localAddress<Scheduler: TCPSocketOperationScheduler>(
    connection: (any Sendable)?,
    on scheduler: Scheduler
  ) throws(IOError) -> SocketAddress {
    try scheduler.localAddress(of: Self.connection(connection, of: scheduler))
  }

  /// Reads once from the socket into the free capacity of the given buffer.
  ///
  /// The bytes are appended to the buffer. A read can return fewer bytes than the free capacity of the buffer.
  ///
  /// - Parameter buffer: The buffer to read into.
  /// - Returns: The number of bytes read. Zero indicates that the peer closed its side of the connection, or
  ///   that the buffer has no free capacity.
  @discardableResult
  public mutating func read(into buffer: inout OutputRawSpan) async throws(IOError) -> Int {
    try await Self.read(into: &buffer, connection: self.connection, on: self.scheduler)
  }

  private static func read<Scheduler: TCPSocketOperationScheduler>(
    into buffer: inout OutputRawSpan,
    connection: (any Sendable)?,
    on scheduler: Scheduler
  ) async throws(IOError) -> Int {
    let connection = Self.connection(connection, of: scheduler)
    let count = try await withOperation(on: scheduler, of: Int.self) { continuation, state in
      scheduler.submitRead(
        continuation,
        state: &state,
        connection: connection,
        into: &buffer
      )
    }

    // The scheduler wrote into the free capacity of the buffer we have
    // to update the initialized count now.
    unsafe buffer.withUnsafeMutableBytes { _, initializedCount in
      initializedCount += count
    }
    return count
  }

  /// Writes all bytes of the given buffer to the socket.
  ///
  /// This can take several writes if the platform accepts only part of the bytes at a time.
  ///
  /// - Parameter buffer: The buffer to write.
  public mutating func write(from buffer: RawSpan) async throws(IOError) {
    try await Self.write(from: buffer, connection: self.connection, on: self.scheduler)
  }

  private static func write<Scheduler: TCPSocketOperationScheduler>(
    from buffer: RawSpan,
    connection: (any Sendable)?,
    on scheduler: Scheduler
  ) async throws(IOError) {
    let connection = Self.connection(connection, of: scheduler)
    var remaining = buffer
    while !remaining.isEmpty {
      let count = try await withOperation(
        on: scheduler,
        of: Int.self
      ) { continuation, state in
        scheduler.submitWrite(
          continuation,
          state: &state,
          connection: connection,
          from: remaining
        )
      }
      remaining = remaining.extracting(droppingFirst: count)
    }
  }

  /// Shuts down one or both directions of the socket.
  ///
  /// Shutting down the write direction sends a `FIN` to the peer, which observes it as the end of the stream
  /// once it has received all data that is still in flight. The socket can still be read from afterwards.
  ///
  /// - Parameter direction: The direction to shut down.
  public mutating func shutdown(_ direction: SocketShutdownDirection) async throws(IOError) {
    try await Self.shutdown(direction, connection: self.connection, on: self.scheduler)
  }

  private static func shutdown<Scheduler: TCPSocketOperationScheduler>(
    _ direction: SocketShutdownDirection,
    connection: (any Sendable)?,
    on scheduler: Scheduler
  ) async throws(IOError) {
    let connection = Self.connection(connection, of: scheduler)
    try await withOperation(on: scheduler, of: Void.self) { continuation, state in
      scheduler.submitShutdown(continuation, state: &state, connection: connection, direction: direction)
    }
  }

  /// Closes the socket.
  public consuming func close() async throws(IOError) {
    try await Self.close(self.connection.take(), on: self.scheduler)
  }

  private static func close<Scheduler: TCPSocketOperationScheduler>(
    _ connection: (any Sendable)?,
    on scheduler: Scheduler
  ) async throws(IOError) {
    let connection = connection as! Scheduler.TCPConnection
    try await withTaskCancellationShield { () async throws(IOError) -> Void in
      try await withOperation(on: scheduler, of: Void.self) { continuation, state in
        scheduler.submitClose(continuation, state: &state, connection: connection)
      }
    }
  }

  /// Returns the handle of the socket as the handle type of the given scheduler.
  ///
  /// - Parameters:
  ///   - connection: The erased handle of the socket.
  ///   - scheduler: The scheduler that services the socket.
  private static func connection<Scheduler: TCPSocketOperationScheduler>(
    _ connection: (any Sendable)?,
    of scheduler: Scheduler
  ) -> Scheduler.TCPConnection {
    // The handle was created by this scheduler, and it is only `nil` once
    // the socket is closed, which consumes it. So the cast cannot fail.
    connection as! Scheduler.TCPConnection
  }

  deinit {
    if self.connection != nil {
      fatalError("A TCPConnection was destroyed without being closed.")
    }
  }
}

// MARK: - Reading and writing concurrently

@available(anyAppleOS 27.0, *)
extension TCPConnection {
  /// The read direction of a connection, lent out by ``TCPConnection/withSplit(_:)``.
  public struct ReadHalf: ~Copyable, ~Escapable, Sendable {
    /// The scheduler that services the socket.
    private let scheduler: any TCPSocketOperationScheduler

    /// The scheduler's handle of the socket.
    private let connection: (any Sendable)?

    @_lifetime(borrow owner)
    fileprivate init(_ owner: borrowing TCPConnection) {
      self.scheduler = owner.scheduler
      self.connection = owner.connection
    }

    /// Reads once from the socket into the free capacity of the given buffer.
    ///
    /// The bytes are appended to the buffer. A read can return fewer bytes than the free capacity of the
    /// buffer.
    ///
    /// - Parameter buffer: The buffer to read into.
    /// - Returns: The number of bytes read. Zero indicates that the peer closed its side of the connection, or
    ///   that the buffer has no free capacity.
    @discardableResult
    public func read(into buffer: inout OutputRawSpan) async throws(IOError) -> Int {
      try await TCPConnection.read(into: &buffer, connection: self.connection, on: self.scheduler)
    }
  }

  /// The write direction of a connection, lent out by ``TCPConnection/withSplit(_:)``.
  public struct WriteHalf: ~Copyable, ~Escapable, Sendable {
    /// The scheduler that services the socket.
    private let scheduler: any TCPSocketOperationScheduler

    /// The scheduler's handle of the socket.
    private let connection: (any Sendable)?

    @_lifetime(borrow owner)
    fileprivate init(_ owner: borrowing TCPConnection) {
      self.scheduler = owner.scheduler
      self.connection = owner.connection
    }

    /// Writes all bytes of the given buffer to the socket.
    ///
    /// This can take several writes if the platform accepts only part of the bytes at a time.
    ///
    /// - Parameter buffer: The buffer to write.
    public func write(from buffer: RawSpan) async throws(IOError) {
      try await TCPConnection.write(from: buffer, connection: self.connection, on: self.scheduler)
    }

    /// Shuts down the write direction of the socket.
    ///
    /// This sends a `FIN` to the peer, which observes it as the end of the stream once it has received all
    /// data that is still in flight.
    public func shutdown() async throws(IOError) {
      try await TCPConnection.shutdown(.write, connection: self.connection, on: self.scheduler)
    }
  }

  /// Lends the read and the write direction of the connection to the given closure.
  ///
  /// The halves can be used concurrently allowing protocols to sends and receives independently.
  ///
  /// ```swift
  /// let reply = try await connection.withSplit { readHalf, writeHalf in
  ///   let (reply, _) = try await withConcurrently {
  ///     try await readReply(from: readHalf)
  ///   } _: {
  ///     try await writeHalf.write(from: request.bytes)
  ///     try await writeHalf.shutdown()
  ///   }
  ///   return reply
  /// }
  /// ```
  ///
  /// - Important: The halves cannot escape the closure, so the connection keeps owning the socket
  /// and must still be closed afterwards.
  ///
  /// - Parameter body: The closure that the halves are lent to.
  /// - Returns: The value that the closure returned.
  public nonisolated(nonsending) func withSplit<Return, Failure: Error>(
    _ body: nonisolated(nonsending) (borrowing ReadHalf, borrowing WriteHalf) async throws(Failure) -> Return
  ) async throws(Failure) -> Return {
    let readHalf = ReadHalf(self)
    let writeHalf = WriteHalf(self)
    return try await body(readHalf, writeHalf)
  }
}
#endif
