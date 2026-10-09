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
#if os(Linux) || os(Android) || os(FreeBSD) || canImport(Darwin)
@_spi(ExperimentalScheduling) @_spi(ConcurrencyExecutors) @_spi(ExperimentalCustomExecutors) import _Concurrency

// MARK: - TCP socket operations

/// A pool forwards every operation to the executor that services the socket. A socket stays on the executor
/// that created it.
@available(anyAppleOS 27.0, *)
extension PThreadTaskExecutor: TCPSocketOperationScheduler {
  public typealias OperationState = PThreadOperationState
  public typealias TCPConnection = PThreadTCPConnection
  public typealias TCPListener = PThreadTCPListener

  public func cancel(_ registration: OperationRegistration) {
    guard let (executorIndex, registration) = self.executorRegistration(of: registration) else {
      return
    }
    self.executors[executorIndex].cancel(registration)
  }

  public func escalatePriority(
    of registration: OperationRegistration,
    to newPriority: TaskPriority
  ) {
    guard let (executorIndex, registration) = self.executorRegistration(of: registration) else {
      return
    }
    self.executors[executorIndex].escalatePriority(of: registration, to: newPriority)
  }

  public func submitConnect(
    _ continuation: consuming Continuation<TCPConnection, IOError>,
    state: inout OutputSpan<OperationState>,
    to address: SocketAddress
  ) -> OperationRegistration {
    let executor = self.next()
    let registration = executor.submitConnect(continuation, state: &state, to: address)
    return self.poolRegistration(of: registration, executorIndex: executor.poolIndex)
  }

  public func submitListen(
    _ continuation: consuming Continuation<TCPListener, IOError>,
    state: inout OutputSpan<OperationState>,
    on address: SocketAddress,
    backlog: Int
  ) -> OperationRegistration {
    let executor = self.next()
    let registration = executor.submitListen(continuation, state: &state, on: address, backlog: backlog)
    return self.poolRegistration(of: registration, executorIndex: executor.poolIndex)
  }

  public func submitAccept(
    _ continuation: consuming Continuation<TCPConnection, IOError>,
    state: inout OutputSpan<OperationState>,
    listener: borrowing TCPListener
  ) -> OperationRegistration {
    let executorIndex = listener.executorIndex
    let registration = self.executors[executorIndex].submitAccept(continuation, state: &state, listener: listener)
    return self.poolRegistration(of: registration, executorIndex: executorIndex)
  }

  public func submitRead(
    _ continuation: consuming Continuation<Int, IOError>,
    state: inout OutputSpan<OperationState>,
    connection: borrowing TCPConnection,
    into buffer: inout OutputRawSpan
  ) -> OperationRegistration {
    let executorIndex = connection.executorIndex
    let registration = self.executors[executorIndex].submitRead(
      continuation,
      state: &state,
      connection: connection,
      into: &buffer
    )
    return self.poolRegistration(of: registration, executorIndex: executorIndex)
  }

  public func submitWrite(
    _ continuation: consuming Continuation<Int, IOError>,
    state: inout OutputSpan<OperationState>,
    connection: borrowing TCPConnection,
    from buffer: RawSpan
  ) -> OperationRegistration {
    let executorIndex = connection.executorIndex
    let registration = self.executors[executorIndex].submitWrite(
      continuation,
      state: &state,
      connection: connection,
      from: buffer
    )
    return self.poolRegistration(of: registration, executorIndex: executorIndex)
  }

  public func submitShutdown(
    _ continuation: consuming Continuation<Void, IOError>,
    state: inout OutputSpan<OperationState>,
    connection: borrowing TCPConnection,
    direction: SocketShutdownDirection
  ) -> OperationRegistration {
    let executorIndex = connection.executorIndex
    let registration = self.executors[executorIndex].submitShutdown(
      continuation,
      state: &state,
      connection: connection,
      direction: direction
    )
    return self.poolRegistration(of: registration, executorIndex: executorIndex)
  }

  public func submitClose(
    _ continuation: consuming Continuation<Void, IOError>,
    state: inout OutputSpan<OperationState>,
    connection: consuming TCPConnection
  ) -> OperationRegistration {
    let executorIndex = connection.executorIndex
    let registration = self.executors[executorIndex].submitClose(continuation, state: &state, connection: connection)
    return self.poolRegistration(of: registration, executorIndex: executorIndex)
  }

  public func submitClose(
    _ continuation: consuming Continuation<Void, IOError>,
    state: inout OutputSpan<OperationState>,
    listener: consuming TCPListener
  ) -> OperationRegistration {
    let executorIndex = listener.executorIndex
    let registration = self.executors[executorIndex].submitClose(continuation, state: &state, listener: listener)
    return self.poolRegistration(of: registration, executorIndex: executorIndex)
  }

  public func localAddress(of connection: borrowing TCPConnection) throws(IOError) -> SocketAddress {
    try self.executors[connection.executorIndex].localAddress(of: connection)
  }

  public func localAddress(of listener: borrowing TCPListener) throws(IOError) -> SocketAddress {
    try self.executors[listener.executorIndex].localAddress(of: listener)
  }
}

#endif
#endif
