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
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// The operations that a readiness based backend is waiting on.
///
/// A readiness based platform only reports that a file descriptor became ready, so this is the half of "wait until
/// readable, then read" that `kqueue` and `epoll` have in common: an operation that cannot be performed right
/// away is parked here and performed once its file descriptor is reported as ready.
///
/// This never touches a selector. Every change to the table hands back the ``Registration`` that the backend
/// then arms.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
struct ReadinessOperations: ~Copyable {
  /// The interest that a backend has to arm for one file descriptor.
  struct Registration {
    /// The file descriptor to arm.
    var fileDescriptor: CInt

    /// The events to arm.
    var interest: ReadinessInterest

    /// The identifier to report back with an event of this registration.
    var registrationID: UInt32
  }

  /// One operation that is waiting for its file descriptor to become ready.
  struct PendingOperation {
    var operation: IOOperation
    var id: IOOperationID
  }

  /// The operations that are waiting on one file descriptor.
  private struct PendingOperations {
    var read: PendingOperation?
    var write: PendingOperation?

    /// The identifier to report back with an event of this registration.
    var registrationID: UInt32

    /// The interest that the pending operations need.
    var interest: ReadinessInterest {
      var interest = ReadinessInterest()
      if self.read != nil {
        interest.insert(.read)
      }
      if self.write != nil {
        interest.insert(.write)
      }
      return interest
    }

    func pending(_ direction: ReadinessInterest) -> PendingOperation? {
      direction == .read ? self.read : self.write
    }

    mutating func setPending(_ pending: PendingOperation?, _ direction: ReadinessInterest) {
      if direction == .read {
        self.read = pending
      } else {
        self.write = pending
      }
    }
  }

  /// The operations that are waiting, keyed by the file descriptor they are waiting on.
  private var pendingOperations: [CInt: PendingOperations] = [:]

  /// The file descriptor that an operation is waiting on, so that cancelling only needs its identity.
  private var fileDescriptors: [IOOperationID: CInt] = [:]

  /// The results that are ready to be handed over to the executor.
  private var readyResults: [(IOOperationID, Result<Int, IOError>)] = []

  /// The identifier of the next registration.
  private var nextRegistrationID: UInt32 = 1

  #if DEBUG
  /// The operations that were submitted and have not resolved yet. This is for debug only purposes.
  private var unresolved: Set<IOOperationID> = []
  #endif

  #if DEBUG
  deinit {
    // An operation that is still here has a submitter that is suspended on it.
    precondition(
      self.unresolved.isEmpty && self.readyResults.isEmpty,
      """
      \(self.unresolved.count + self.readyResults.count) operation(s) were still in flight when
      the executor tore its I/O down.
      """
    )
  }
  #endif

  /// Records that an operation was submitted.
  private mutating func trackSubmitted(_ id: IOOperationID) {
    #if DEBUG
    precondition(
      self.unresolved.insert(id).inserted,
      """
      An operation was submitted while one with the same identity is still in flight.
      """
    )
    #endif
  }

  /// Resolves an operation.
  private mutating func resolve(_ id: IOOperationID, with result: Result<Int, IOError>) {
    #if DEBUG
    precondition(
      self.unresolved.remove(id) != nil,
      """
      An operation reported a second result.
      """
    )
    #endif
    self.readyResults.append((id, result))
  }

  // MARK: - Performing operations

  /// Performs the operation if it can be performed without waiting.
  ///
  /// - Parameter operation: The operation to perform.
  /// - Returns: The result of the operation, or `nil` if it cannot be performed without waiting.
  static func attempt(_ operation: IOOperation) -> Result<Int, IOError>? {
    switch operation {
    case .connect(let socket, let address, let addressLength):
      do {
        return try StreamSocketSyscall.connect(
          socket,
          to: address,
          addressLength: addressLength
        ) ? .success(0) : nil
      } catch {
        return .failure(error)
      }

    case .accept(let socket):
      do {
        return try StreamSocketSyscall.accept(socket).map { .success(Int($0)) }
      } catch {
        return .failure(error)
      }

    case .read(let socket, let buffer):
      do {
        return try StreamSocketSyscall.receive(socket, into: buffer).map { .success($0) }
      } catch {
        return .failure(error)
      }

    case .write(let socket, let buffer):
      do {
        return try StreamSocketSyscall.send(socket, from: buffer).map { .success($0) }
      } catch {
        return .failure(error)
      }

    case .shutdown(let socket, let direction):
      do {
        try StreamSocketSyscall.shutdown(socket, direction: direction)
        return .success(0)
      } catch {
        return .failure(error)
      }

    case .close:
      // A close has to be ordered against the operations that are still waiting
      // on the socket, and only the  executor's thread knows about those, so a
      // close is never performed here.
      return nil
    }
  }

  /// Performs an operation whose file descriptor just became ready.
  ///
  /// This differs from ``attempt(_:)`` in just one place: a connect was already started by the attempt,
  /// so its result is read from the socket rather than by connecting again.
  private static func perform(_ operation: IOOperation) -> Result<Int, IOError>? {
    guard case .connect(let socket, _, _) = operation else {
      return Self.attempt(operation)
    }

    do {
      let errnoCode = try StreamSocketSyscall.pendingError(socket)
      guard errnoCode == 0 else {
        return .failure(IOError(errnoCode: errnoCode))
      }
      return .success(0)
    } catch {
      return .failure(error)
    }
  }

  /// The direction that an operation waits for.
  private static func direction(of operation: IOOperation) -> ReadinessInterest {
    switch operation {
    case .connect, .write:
      return .write
    case .accept, .read:
      return .read
    case .shutdown, .close:
      // Neither waits for readiness.
      return .read
    }
  }

  // MARK: - Submitting

  /// Parks an operation until its file descriptor becomes ready.
  ///
  /// - Parameters:
  ///   - operation: The operation to submit.
  ///   - id: The identity to report the result of the operation with.
  /// - Returns: The registration that the caller has to arm, or `nil` if nothing has to be armed.
  mutating func submit(_ operation: IOOperation, id: IOOperationID) -> Registration? {
    self.trackSubmitted(id)

    switch operation {
    case .close(let socket):
      // Everything that is still waiting on the socket has to be failed before
      // the socket goes away.
      // TODO: We might want to use a different error code here than cancelled.
      self.failPendingOperations(on: socket, with: IOError(code: .cancelled))
      do {
        try StreamSocketSyscall.close(socket)
        self.resolve(id, with: .success(0))
      } catch {
        self.resolve(id, with: .failure(error))
      }
      return nil

    case .shutdown(let socket, let direction):
      do {
        try StreamSocketSyscall.shutdown(socket, direction: direction)
        self.resolve(id, with: .success(0))
      } catch {
        self.resolve(id, with: .failure(error))
      }
      return nil

    case .connect, .accept, .read, .write:
      break
    }

    let fileDescriptor = operation.fileDescriptor
    let direction = Self.direction(of: operation)

    var pending =
      self.pendingOperations[fileDescriptor]
      ?? PendingOperations(registrationID: self.makeRegistrationID())
    precondition(
      pending.pending(direction) == nil,
      "A file descriptor can only have one read and one write in flight at a time"
    )

    pending.setPending(PendingOperation(operation: operation, id: id), direction)
    self.fileDescriptors[id] = fileDescriptor
    return self.store(pending, for: fileDescriptor)
  }

  /// Cancels a submitted operation.
  ///
  /// - Parameter id: The identity of the operation to cancel.
  /// - Returns: The registration that the caller has to arm, or `nil` if nothing has to be armed.
  mutating func cancel(_ id: IOOperationID) -> Registration? {
    guard let fileDescriptor = self.fileDescriptors.removeValue(forKey: id),
      var pending = self.pendingOperations[fileDescriptor]
    else {
      // The operation completed already.
      return nil
    }

    if pending.read?.id == id {
      pending.read = nil
    } else if pending.write?.id == id {
      pending.write = nil
    } else {
      return nil
    }

    self.resolve(id, with: .failure(IOError(code: .cancelled)))
    return self.store(pending, for: fileDescriptor)
  }

  // MARK: - Reporting results

  /// Whether there are results waiting to be handed over.
  var hasReadyResults: Bool {
    !self.readyResults.isEmpty
  }

  /// Hands over every result that became available.
  ///
  /// - Parameter completions: The array to move the results into. It has to be empty.
  mutating func takeReadyResults(into completions: inout [(IOOperationID, Result<Int, IOError>)]) {
    assert(completions.isEmpty, "The results can only be handed over into an empty array")
    swap(&completions, &self.readyResults)
  }

  /// Performs the operations of a file descriptor that became ready.
  ///
  /// - Parameter event: The event that the backend reported.
  /// - Returns: The registration that the caller has to arm, or `nil` if nothing waits on the file descriptor anymore.
  mutating func handle(_ event: ReadinessEvent) -> Registration? {
    guard var pending = self.pendingOperations[event.fileDescriptor],
      pending.registrationID == event.registrationID
    else {
      // The event belongs to a registration that is gone, for example because
      // the file descriptor was closed and has been recycled since.
      return nil
    }

    // A file descriptor has at most one read and one write pending,
    // so each direction is handled on its own.
    if event.isReadable || event.isError {
      self.performPending(.read, of: &pending)
    }
    if event.isWritable || event.isError {
      self.performPending(.write, of: &pending)
    }

    return self.store(pending, for: event.fileDescriptor)
  }

  /// Performs the operation that waits in the given direction, if there is one.
  ///
  /// - Parameters:
  ///   - direction: The direction that became ready.
  ///   - pending: The operations that wait on the file descriptor.
  private mutating func performPending(_ direction: ReadinessInterest, of pending: inout PendingOperations) {
    guard let operation = pending.pending(direction) else {
      return
    }
    guard let result = Self.perform(operation.operation) else {
      // The file descriptor was reported as ready but the operation
      // would still block, so it waits again.
      return
    }
    pending.setPending(nil, direction)
    self.fileDescriptors.removeValue(forKey: operation.id)
    self.resolve(operation.id, with: result)
  }

  // MARK: - Registering

  /// Stores the pending operations of a file descriptor and returns the registration they need.
  private mutating func store(
    _ pending: PendingOperations,
    for fileDescriptor: CInt
  ) -> Registration? {
    let interest = pending.interest
    guard !interest.isEmpty else {
      self.pendingOperations.removeValue(forKey: fileDescriptor)
      return nil
    }

    self.pendingOperations[fileDescriptor] = pending
    return Registration(
      fileDescriptor: fileDescriptor,
      interest: interest,
      registrationID: pending.registrationID
    )
  }

  /// Fails every operation that is waiting on the file descriptor and forgets it.
  mutating func failPendingOperations(
    on fileDescriptor: CInt,
    with error: IOError
  ) {
    guard let pending = self.pendingOperations.removeValue(forKey: fileDescriptor) else {
      return
    }

    for operation in [pending.read, pending.write] {
      guard let operation else {
        continue
      }
      self.fileDescriptors.removeValue(forKey: operation.id)
      self.resolve(operation.id, with: .failure(error))
    }
  }

  /// The registration that the operations of a file descriptor.
  ///
  /// - Parameter fileDescriptor: The file descriptor to return the registration of.
  /// - Returns: The registration to arm, or `nil` if nothing waits on the file descriptor anymore.
  func registration(for fileDescriptor: CInt) -> Registration? {
    guard let pending = self.pendingOperations[fileDescriptor] else {
      return nil
    }
    return Registration(
      fileDescriptor: fileDescriptor,
      interest: pending.interest,
      registrationID: pending.registrationID
    )
  }

  /// Returns the identifier for a new registration.
  private mutating func makeRegistrationID() -> UInt32 {
    let id = self.nextRegistrationID
    self.nextRegistrationID = id == .max ? 1 : id + 1
    return id
  }
}
#endif
#endif
