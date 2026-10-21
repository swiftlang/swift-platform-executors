//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2024 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if canImport(Darwin)
import Darwin
#if ExperimentalIO
internal import BasicContainers
#endif

private let sysKevent = unsafe kevent

/// An I/O mechanism that uses kqueue for eventing.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@safe
struct KQueueReadinessBackend: ~Copyable {
  /// A handle that other threads use to wake this backend up.
  struct WakeupHandle: Sendable {
    /// The kqueue file descriptor never changes so we can use it to wakeup the selector from any thread.
    fileprivate let kqueueFD: CInt
  }

  /// The file descriptor of the queue.
  fileprivate var kqueueFD: CInt

  /// The registration changes that have not been applied yet.
  ///
  /// kqueue takes a changelist in the same call that waits for events, so changes are accumulated here and
  /// applied by the next wait.
  private var pendingChanges: UniqueArray<Darwin.kevent> = {
    var pendingChanges = unsafe UniqueArray<Darwin.kevent>()
    #if ExperimentalIO
    unsafe pendingChanges.reserveCapacity(IOOperation.reservedCapacity)
    #endif
    return unsafe pendingChanges
  }()

  /// A handle that other threads use to wake this backend up.
  var wakeupHandle: WakeupHandle {
    WakeupHandle(kqueueFD: self.kqueueFD)
  }
  /// The deadline that the continuous clock timer is armed for, to avoid re-arming it for a later one.
  fileprivate var armedContinuousClockDeadline: ContinuousClock.Instant?
  /// The deadline that the suspending clock timer is armed for, to avoid re-arming it for a later one.
  fileprivate var armedSuspendingClockDeadline: SuspendingClock.Instant?

  #if ExperimentalIO
  /// The operations that are waiting for their file descriptor to become ready.
  private var operations = ReadinessOperations()

  /// The events buffer.
  private var events = unsafe UniqueArray<Darwin.kevent>(
    minimumCapacity: IOOperation.reservedCapacity
  )
  #endif

  init() throws {
    self.kqueueFD = try! Self.kqueue()

    var event = unsafe Darwin.kevent()
    unsafe event.ident = 0
    unsafe event.filter = Int16(EVFILT_USER)
    unsafe event.fflags = UInt32(NOTE_FFNOP)
    unsafe event.data = 0
    unsafe event.udata = nil
    unsafe event.flags = UInt16(EV_ADD | EV_ENABLE | EV_CLEAR)
    try withUnsafeMutablePointer(to: &event) { ptr in
      try unsafe Self.kqueueApplyEventChangeSet(
        kqueueFD: kqueueFD,
        keventBuffer: UnsafeMutableBufferPointer(start: ptr, count: 1)
      )
    }
  }

  deinit {
    // We try! all of the closes because close can only fail in the following ways:
    // - EINTR, which we eat in close
    // - EIO, which can only happen for on-disk files
    // - EBADF, which can't happen here because we would crash as EBADF is marked unacceptable
    // Therefore, we assert here that close will always succeed and if not, that's a bug we need to know
    // about.
    try! close(descriptor: self.kqueueFD)
  }

  @inline(never)
  fileprivate static func kqueue() throws -> CInt {
    return try retryingSyscall(blocking: false) {
      Darwin.kqueue()
    }.result
  }

  @inline(never)
  @discardableResult
  fileprivate static func kevent(
    kq: CInt,
    changelist: UnsafePointer<kevent>?,
    nchanges: CInt,
    eventlist: UnsafeMutablePointer<kevent>?,
    nevents: CInt,
    timeout: UnsafePointer<Darwin.timespec>?
  ) throws -> CInt {
    return try retryingSyscall(blocking: false) {
      unsafe sysKevent(kq, changelist, nchanges, eventlist, nevents, timeout)
    }.result
  }

  /// Apply a kqueue changeset by calling the `kevent` function with the `kevent`s supplied in `keventBuffer`.
  private static func kqueueApplyEventChangeSet(
    kqueueFD: CInt,
    keventBuffer: UnsafeMutableBufferPointer<kevent>
  ) throws {
    guard keventBuffer.count > 0 else {
      // nothing to do
      return
    }
    do {
      try unsafe Self.kevent(
        kq: kqueueFD,
        changelist: keventBuffer.baseAddress!,
        nchanges: CInt(keventBuffer.count),
        eventlist: nil,
        nevents: 0,
        timeout: nil
      )
    } catch let err as SyscallError {
      if err.errnoCode == EINTR {
        // See https://www.freebsd.org/cgi/man.cgi?query=kqueue&sektion=2
        // When kevent() call fails with EINTR error, all changes in the changelist have been applied.
        return
      }
      throw err
    }
  }

  private static func toKQueueTimeSpec(strategy: IOWaitStrategy) -> timespec? {
    switch strategy {
    case .block:
      return nil
    case .blockUntilTimeout:
      // Timer events will be handled by kqueue EVFILT_TIMER, so we block indefinitely
      return nil
    case .now:
      return timespec(tv_sec: 0, tv_nsec: 0)
    }
  }

  /// The maximum number of events that are processed in a single tick.
  private static var maxEvents: Int { 64 }

  /// Blocks until a registered file descriptor became ready, a timer fired or the wakeup was called.
  ///
  /// - Parameters:
  ///   - strategy: The strategy to use for blocking.
  /// Returns the timeout of `kevent` for the strategy.
  private mutating func prepareWait(strategy: IOWaitStrategy) -> timespec? {
    self.appendTimerChanges(strategy: strategy)
    return Self.toKQueueTimeSpec(strategy: strategy)
  }

  /// Applies the changelist, waits for events and writes them into the given output span.
  private static func waitForEvents(
    kqueueFD: CInt,
    changelist: UnsafeBufferPointer<Darwin.kevent>,
    timeout: timespec?,
    into events: inout OutputSpan<Darwin.kevent>
  ) throws {
    try unsafe events.withUnsafeMutableBufferPointer { buffer, initializedCount in
      assert(initializedCount == 0, "The events can only be written into an empty buffer")
      initializedCount = try unsafe timeout.withUnsafeOptionalPointer { ts in
        unsafe Int(
          try Self.kevent(
            kq: kqueueFD,
            changelist: changelist.baseAddress,
            nchanges: CInt(changelist.count),
            eventlist: buffer.baseAddress!,
            nevents: CInt(buffer.count),
            timeout: ts
          )
        )
      }
    }
  }

  /// Processes one event that ``waitForEvents(strategy:into:)`` handed back.
  ///
  /// - Parameter event: The event to process.
  /// - Returns: The readiness of a file descriptor that an operation waits on, or `nil` if the event was one of
  ///   this backend's own or an expected failure of a change.
  private mutating func process(_ event: Darwin.kevent) -> ReadinessEvent? {
    if unsafe event.flags & UInt16(EV_ERROR) != 0 {
      // A change of the changelist failed. Applying changes in batches means
      // we can queue up a delete for a one-shot registration that the kernel
      // removed already, or for a file descriptor that was closed in the meantime,
      // so those two are expected and dropped.
      let errnoCode = unsafe CInt(event.data)
      if errnoCode == ENOENT || errnoCode == EBADF {
        return nil
      }
    }
    switch unsafe Int16(event.filter) {
    case Int16(EVFILT_USER):
      // User wakeup event - nothing to do, just unblocks
      return nil
    case Int16(EVFILT_TIMER):
      // Timer event - reset the corresponding timer state
      switch unsafe Int(event.ident) {
      case 1:
        // The continuous clock timer fired so it is not armed anymore.
        self.armedContinuousClockDeadline = nil
      case 2:
        // The suspending clock timer fired so it is not armed anymore.
        self.armedSuspendingClockDeadline = nil
      default:
        fatalError(unsafe "Unknown timer identifier in kqueue event: \(event.ident)")
      }
      return nil
    case Int16(EVFILT_READ), Int16(EVFILT_WRITE):
      let isRead = unsafe Int16(event.filter) == Int16(EVFILT_READ)
      return unsafe ReadinessEvent(
        registrationID: UInt32(UInt(bitPattern: event.udata)),
        fileDescriptor: CInt(event.ident),
        // `EV_EOF` is reported alongside readiness and the operation that
        // follows surfaces the end of the stream, so we treat it as being ready.
        isReadable: isRead,
        isWritable: !isRead,
        isError: event.flags & UInt16(EV_ERROR) != 0
      )
    default:
      fatalError(unsafe "Unknown filter type in kqueue event: \(event.filter)")
    }
  }

  /// Appends the timer changes for the given strategy.
  private mutating func appendTimerChanges(strategy: IOWaitStrategy) {
    guard case .blockUntilTimeout(let continuousClockInstant, let suspendingClockInstant) = strategy else {
      return
    }

    // Set up continuous clock timer (ident = 1)
    if let continuousClockInstant {
      let shouldSetTimer: Bool
      if let armedContinuousClockDeadline = self.armedContinuousClockDeadline {
        // Only set timer if new deadline is earlier
        shouldSetTimer = continuousClockInstant < armedContinuousClockDeadline
      } else {
        shouldSetTimer = true
      }

      if shouldSetTimer {
        let duration = ContinuousClock.now.duration(
          to: continuousClockInstant
        )
        let nanoseconds =
          Int(duration.components.seconds) * 1_000_000_000 + Int(duration.components.attoseconds / 1_000_000_000)
        unsafe self.pendingChanges.append(Self.timerEvent(ident: 1, nanoseconds: nanoseconds))
        self.armedContinuousClockDeadline = continuousClockInstant
      }
    }

    // Set up suspending clock timer (ident = 2)
    if let suspendingClockInstant {
      let shouldSetTimer: Bool
      if let armedSuspendingClockDeadline = self.armedSuspendingClockDeadline {
        // Only set timer if new deadline is earlier
        shouldSetTimer = suspendingClockInstant < armedSuspendingClockDeadline
      } else {
        shouldSetTimer = true
      }

      if shouldSetTimer {
        let duration = SuspendingClock.now.duration(
          to: suspendingClockInstant
        )
        let nanoseconds =
          Int(duration.components.seconds) * 1_000_000_000 + Int(duration.components.attoseconds / 1_000_000_000)
        unsafe self.pendingChanges.append(Self.timerEvent(ident: 2, nanoseconds: nanoseconds))
        self.armedSuspendingClockDeadline = suspendingClockInstant
      }
    }
  }

  /// The change that arms a kqueue timer for the given instant.
  private static func timerEvent(ident: Int, nanoseconds: Int) -> Darwin.kevent {
    var event = unsafe Darwin.kevent()
    unsafe event.ident = UInt(ident)
    unsafe event.filter = Int16(EVFILT_TIMER)
    unsafe event.flags = UInt16(EV_ADD | EV_ENABLE | EV_ONESHOT)
    unsafe event.fflags = UInt32(NOTE_NSECONDS)
    unsafe event.data = nanoseconds
    unsafe event.udata = nil
    return unsafe event
  }

  /// Wakes up a backend from any thread.
  ///
  /// - Parameter handle: The handle of the backend to wake up.
  static func wakeup(_ handle: WakeupHandle) throws {
    var event = unsafe Darwin.kevent()
    unsafe event.ident = 0
    unsafe event.filter = Int16(EVFILT_USER)
    unsafe event.fflags = UInt32(NOTE_TRIGGER | NOTE_FFNOP)
    unsafe event.data = 0
    unsafe event.udata = nil
    unsafe event.flags = 0
    try withUnsafeMutablePointer(to: &event) { ptr in
      try unsafe Self.kqueueApplyEventChangeSet(
        kqueueFD: handle.kqueueFD,
        keventBuffer: UnsafeMutableBufferPointer(start: ptr, count: 1)
      )
    }
  }

  #if ExperimentalIO
  /// Arms the interest of a registration.
  ///
  /// The registrations are one-shot, so kqueue removes them as soon as they produced an event and an
  /// operation that has to wait again needs to be re-armed.
  private mutating func arm(_ registration: ReadinessOperations.Registration) {
    let filters = [
      (EVFILT_READ, registration.interest.contains(.read)),
      (EVFILT_WRITE, registration.interest.contains(.write)),
    ]
    for (filter, isInterested) in filters where isInterested {
      var event = unsafe Darwin.kevent()
      unsafe event.ident = UInt(UInt32(bitPattern: registration.fileDescriptor))
      unsafe event.filter = Int16(filter)
      unsafe event.flags = UInt16(EV_ADD | EV_ENABLE | EV_ONESHOT)
      unsafe event.fflags = 0
      unsafe event.data = 0
      unsafe event.udata = unsafe UnsafeMutableRawPointer(bitPattern: UInt(registration.registrationID))
      unsafe self.pendingChanges.append(event)
    }
  }
  #endif
}

#if ExperimentalIO
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension KQueueReadinessBackend: IOBackend {
  static func attempt(_ operation: IOOperation) -> Result<Int, IOError>? {
    unsafe ReadinessOperations.attempt(operation)
  }

  mutating func submit(_ operation: IOOperation, id: IOOperationID) {
    guard let registration = unsafe self.operations.submit(operation, id: id) else {
      // The operation completed on the spot, a close for example.
      return
    }
    self.arm(registration)
  }

  mutating func cancel(_ id: IOOperationID) {
    guard let registration = self.operations.cancel(id) else {
      // Either the operation completed already, or nothing waits on its
      // file descriptor anymore.
      return
    }
    self.arm(registration)
  }

  mutating func wait(
    strategy: IOWaitStrategy,
    completions: inout [(IOOperationID, Result<Int, IOError>)]
  ) throws {
    // Something may have completed without kqueue since the last tick,
    // such as a cancelled operation or a close. Nothing wakes us up for
    // those, so we must not block if there are any.
    var strategy = strategy
    if self.operations.hasReadyResults {
      strategy = .now
    }

    let timeout = self.prepareWait(strategy: strategy)
    let kqueueFD = self.kqueueFD
    unsafe self.events.removeAll()
    try unsafe self.pendingChanges.span.withUnsafeBufferPointer { changelist in
      try unsafe self.events.edit { events in
        try unsafe Self.waitForEvents(
          kqueueFD: kqueueFD,
          changelist: changelist,
          timeout: timeout,
          into: &events
        )
      }
    }
    // The kernel has taken the changes, so we can clear the array.
    unsafe self.pendingChanges.removeAll()

    for index in unsafe self.events.indices {
      // The event is copied out, since processing it mutates the backend.
      let event = unsafe self.events[index]
      guard let readiness = unsafe self.process(event),
        let registration = self.operations.handle(readiness)
      else {
        // The event was one of our own, stale, or
        // nothing waits on the file descriptor anymore.
        continue
      }
      self.arm(registration)
    }

    // The results are handed over last, once everything is armed.
    self.operations.takeReadyResults(into: &completions)
  }
}
#else
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension KQueueReadinessBackend: IOBackend {
  mutating func wait(strategy: IOWaitStrategy) throws {
    let timeout = self.prepareWait(strategy: strategy)
    let kqueueFD = self.kqueueFD
    try withTemporaryAllocation(of: Darwin.kevent.self, capacity: Self.maxEvents) { events in
      try self.pendingChanges.withUnsafeBufferPointer { changelist in
        try Self.waitForEvents(kqueueFD: kqueueFD, changelist: changelist, timeout: timeout, into: &events)
      }
      // The kernel has taken the changes, so we can clear the array.
      self.pendingChanges.removeAll()

      for index in events.indices {
        _ = self.process(events[index])
      }
    }
  }
}
#endif

extension Optional {
  fileprivate func withUnsafeOptionalPointer<T>(
    _ body: (UnsafePointer<Wrapped>?) throws -> T
  ) rethrows -> T {
    guard var this = self else {
      return try body(nil)
    }
    return try withUnsafePointer(to: &this) { x in
      try unsafe body(x)
    }
  }
}
#endif
