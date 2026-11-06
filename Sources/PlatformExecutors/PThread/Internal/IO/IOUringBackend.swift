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

#if ExperimentalIOUring && canImport(Glibc)
import Glibc
import CPlatformExecutors
import SystemPackage
import SystemSockets

/// An I/O mechanism that uses `io_uring`.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@safe
struct IOUringBackend: ~Copyable {
  /// A handle that other threads use to wake this backend up.
  struct WakeupHandle: Sendable {
    /// The event file descriptor that a read request of the ring waits on.
    fileprivate let eventFD: CInt
  }

  /// The ring that the operations are submitted to.
  private var ring: IORing

  /// The event file descriptor that wakes up a wait.
  private let eventFD: CInt

  /// The buffer that the read of ``eventFD`` reads into.
  private let wakeupBuffer: UnsafeMutableRawBufferPointer

  /// The context of the requests whose completions are not reported, such as cancellations. The identities
  /// of operations start at one, so this never belongs to an operation.
  private static var internalContext: UInt64 { 0 }

  /// The context of the read of ``eventFD``.
  private static var wakeupContext: UInt64 { .max }

  /// The number of requests that the ring can hold before they have to be submitted.
  private static var queueDepth: UInt32 { 256 }

  /// A handle that other threads use to wake this backend up.
  var wakeupHandle: WakeupHandle {
    WakeupHandle(eventFD: self.eventFD)
  }

  init() throws {
    let eventFD = try EventFileDescriptor.makeEventFileDescriptor(
      initval: 0,
      flags: Int32(EventFileDescriptor.EFD_CLOEXEC | EventFileDescriptor.EFD_NONBLOCK)
    )
    let ring: IORing
    do {
      ring = try IORing(queueDepth: Self.queueDepth)
    } catch {
      try? close(descriptor: eventFD)
      throw error
    }
    self.ring = ring
    self.eventFD = eventFD
    unsafe self.wakeupBuffer = .allocate(
      byteCount: MemoryLayout<UInt64>.size,
      alignment: MemoryLayout<UInt64>.alignment
    )
    self.armWakeup()
  }

  deinit {
    try! close(descriptor: self.eventFD)
    unsafe self.wakeupBuffer.deallocate()
  }

  /// Wakes up a backend from any thread.
  ///
  /// - Parameter handle: The handle of the backend to wake up.
  static func wakeup(_ handle: WakeupHandle) throws {
    _ = try EventFileDescriptor.eventfd_write(fd: handle.eventFD, value: 1)
  }

  /// Prepares a read of ``eventFD``, so that a write to it completes a request and ends the wait.
  private mutating func armWakeup() {
    unsafe self.prepare(
      .read(
        FileDescriptor(rawValue: self.eventFD),
        into: self.wakeupBuffer,
        // The event file descriptor cannot seek
        // so it is read at its current position.
        at: .max,
        context: Self.wakeupContext
      )
    )
  }

  /// Prepares a request, submitting the prepared ones first if the ring is full.
  private mutating func prepare(_ request: IORing.Request) {
    if self.ring.prepare(request: request) {
      return
    }
    // The submission queue is full, so we hand it to the kernel to make room.
    // Submitting retries interruptions, so a failure means the ring is broken
    // or its completion queue overflowed, and nothing was submitted.
    do {
      try self.ring.submitPreparedRequests()
    } catch {
      fatalError("Submitting the full io_uring submission queue failed: \(error)")
    }
    let isPrepared = self.ring.prepare(request: request)
    precondition(isPrepared, "The io_uring submission queue has no room after submitting it")
  }

  /// Returns the request that performs the operation.
  private static func request(for operation: IOOperation, context: UInt64) -> IORing.Request {
    switch unsafe operation {
    case .connect(let socket, let address, let addressLength):
      return unsafe .connect(
        SocketDescriptor(rawValue: socket),
        to: SystemSockets.SocketAddress(address: address, length: addressLength),
        context: context
      )
    case .accept(let socket):
      // The accepted socket is non-blocking, like the sockets of every backend.
      return .accept(SocketDescriptor(rawValue: socket), flags: [.closeOnExec, .nonBlocking], context: context)
    case .read(let socket, let buffer):
      return unsafe .receive(SocketDescriptor(rawValue: socket), into: buffer, context: context)
    case .write(let socket, let buffer):
      // A send request sets `MSG_NOSIGNAL`, so it fails with `EPIPE` rather
      // than raising `SIGPIPE`.
      return unsafe .send(buffer, to: SocketDescriptor(rawValue: socket), context: context)
    case .sendMessage(let socket, let message):
      return unsafe .sendMessage(message, to: SocketDescriptor(rawValue: socket), context: context)
    case .receiveMessage(let socket, let message):
      return unsafe .receiveMessage(SocketDescriptor(rawValue: socket), into: message, context: context)
    case .shutdown(let socket, let direction):
      let how: SocketDescriptor.ShutdownKind =
        switch direction {
        case .read: .read
        case .write: .write
        case .readWrite: .readWrite
        }
      return .shutdown(SocketDescriptor(rawValue: socket), how, context: context)
    case .close(let socket):
      return .close(FileDescriptor(rawValue: socket), context: context)
    case .openFile(let path, let flags, let permissions):
      // The ring copies the path, so it only has to stay alive until the request is prepared.
      return unsafe .open(
        FilePath(platformString: path),
        in: FileDescriptor(rawValue: AT_FDCWD),
        mode: FileDescriptor.AccessMode(rawValue: flags & O_ACCMODE),
        options: FileDescriptor.OpenOptions(rawValue: flags & ~O_ACCMODE),
        permissions: SystemPackage.FilePermissions(rawValue: permissions),
        context: context
      )
    case .readFile(let file, let buffer, let offset):
      return unsafe .read(FileDescriptor(rawValue: file), into: buffer, at: UInt64(offset), context: context)
    case .writeFile(let file, let buffer, let offset):
      return unsafe .write(
        UnsafeMutableRawBufferPointer(mutating: buffer),
        into: FileDescriptor(rawValue: file),
        at: UInt64(offset),
        context: context
      )
    }
  }

  /// The result of a completion.
  private static func result(of completion: borrowing IORing.Completion) -> Result<Int, IOError> {
    let result = completion.result
    guard result < 0 else {
      return .success(Int(result))
    }
    let errnoCode = -result
    // A cancelled operation reports `ECANCELED`, and one that was interrupted
    // while it was being cancelled `EINTR`.
    if errnoCode == ECANCELED || errnoCode == EINTR {
      return .failure(IOError(code: .cancelled))
    }
    return .failure(IOError(code: .platform(errnoCode)))
  }

  /// Returns how long the wait may block for the given deadlines,
  /// or `nil` to block until something completes.
  private static func timeout(
    continuousClockInstant: ContinuousClock.Instant?,
    suspendingClockInstant: SuspendingClock.Instant?
  ) -> Duration? {
    var timeout: Duration?
    if let continuousClockInstant {
      timeout = ContinuousClock.now.duration(to: continuousClockInstant)
    }
    if let suspendingClockInstant {
      let duration = SuspendingClock.now.duration(to: suspendingClockInstant)
      timeout = min(timeout ?? duration, duration)
    }
    return timeout.map { max($0, .zero) }
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension IOUringBackend: IOBackend {
  static var performsFileOperations: Bool { true }

  static func attempt(_ operation: IOOperation) -> Result<Int, IOError>? {
    // The ring performs every operation.
    nil
  }

  mutating func submit(_ operation: IOOperation, id: IOOperationID) {
    if case .close(let socket) = unsafe operation {
      // This cancels all outstanding requests on the file descriptor.
      // TODO: Once we make the associated types become ~Copyable we don't need this
      self.prepare(.cancel(.all, matching: FileDescriptor(rawValue: socket)))
    }
    unsafe self.prepare(Self.request(for: operation, context: Self.context(of: id)))
  }

  mutating func cancel(_ id: IOOperationID) {
    // The cancelled operation still completes, with `ECANCELED` if it was
    // cancelled in time.
    self.prepare(.cancel(.first, matchingContext: Self.context(of: id)))
  }

  /// Returns the context of the requests of an operation.
  private static func context(of id: IOOperationID) -> UInt64 {
    let context = UInt64(id.rawValue)
    assert(
      context != Self.internalContext && context != Self.wakeupContext,
      "The identity of an operation collides with a reserved request context"
    )
    return context
  }

  mutating func wait(
    strategy: IOWaitStrategy,
    completions: inout [(IOOperationID, Result<Int, IOError>)]
  ) throws {
    let minimumCount: UInt32
    let timeout: Duration?
    switch strategy {
    case .now:
      minimumCount = 0
      timeout = nil
    case .block:
      minimumCount = 1
      timeout = nil
    case .blockUntilTimeout(let continuousClockInstant, let suspendingClockInstant):
      timeout = Self.timeout(
        continuousClockInstant: continuousClockInstant,
        suspendingClockInstant: suspendingClockInstant
      )
      minimumCount = timeout == .zero ? 0 : 1
    }

    var wakeupCompleted = false
    self.ring.submitPreparedRequestsAndConsumeCompletions(
      minimumCount: minimumCount,
      timeout: timeout
    ) { (completion: consuming IORing.Completion?, _, _) in
      // A failure of the ring itself, such as the timeout of the wait or an
      // interrupted wait comes without a completion. The executor waits
      // again on its next tick either way.
      guard let completion else {
        return
      }
      switch completion.context {
      case Self.internalContext:
        break
      case Self.wakeupContext:
        wakeupCompleted = true
      case let context:
        completions.append((IOOperationID(rawValue: UInt(context)), Self.result(of: completion)))
      }
    }
    if wakeupCompleted {
      // The read of the event file descriptor completed
      // so the next one has to be prepared.
      self.armWakeup()
    }
  }
}
#endif
