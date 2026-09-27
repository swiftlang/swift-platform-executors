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

private let sysKevent = kevent

/// An I/O mechanism that uses kqueue for eventing.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
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
  private var pendingChanges: [Darwin.kevent] = []

  /// A handle that other threads use to wake this backend up.
  var wakeupHandle: WakeupHandle {
    WakeupHandle(kqueueFD: self.kqueueFD)
  }
  /// The next continuous clock timer to avoid re-arming the timer if possible.
  fileprivate var nextContinuousClockTimer: ContinuousClock.Instant?
  /// The next suspending clock timer to avoid re-arming the timer if possible.
  fileprivate var nextSuspendingClockTimer: SuspendingClock.Instant?

  init() throws {
    self.kqueueFD = try! Self.kqueue()

    var event = Darwin.kevent()
    event.ident = 0
    event.filter = Int16(EVFILT_USER)
    event.fflags = UInt32(NOTE_FFNOP)
    event.data = 0
    event.udata = nil
    event.flags = UInt16(EV_ADD | EV_ENABLE | EV_CLEAR)
    try withUnsafeMutablePointer(to: &event) { ptr in
      try Self.kqueueApplyEventChangeSet(
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
      sysKevent(kq, changelist, nchanges, eventlist, nevents, timeout)
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
      try Self.kevent(
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

  /// Blocks until a registered file descriptor became ready, a timer fired or the wakeup was called.
  ///
  /// - Parameter strategy: The strategy to use for blocking.
  private mutating func whenReady(strategy: IOWaitStrategy) throws {
    // First we append the timer changes.
    self.appendTimerChanges(strategy: strategy)

    let timespec = Self.toKQueueTimeSpec(strategy: strategy)

    // We need to handle the user event and the two timer events.
    let maxEvents = 3
    try withUnsafeTemporaryAllocation(of: Darwin.kevent.self, capacity: maxEvents) { eventsPointer in
      let readyEvents = try timespec.withUnsafeOptionalPointer { ts in
        try self.pendingChanges.withUnsafeBufferPointer { changelist in
          Int(
            try Self.kevent(
              kq: self.kqueueFD,
              changelist: changelist.baseAddress,
              nchanges: CInt(changelist.count),
              eventlist: eventsPointer.baseAddress!,
              nevents: CInt(maxEvents),
              timeout: ts
            )
          )
        }
      }
      // The kernel has taken the changes, so we can clear the array.
      self.pendingChanges.removeAll(keepingCapacity: true)

      // Process the ready events
      for i in 0..<readyEvents {
        let event = eventsPointer[i]
        if event.flags & UInt16(EV_ERROR) != 0 {
          // A change of the changelist failed. Applying changes in batches means we can queue up a delete for
          // a one-shot registration that the kernel removed already, or for a file descriptor that was closed
          // in the meantime, so those two are expected and dropped.
          let errnoCode = CInt(event.data)
          if errnoCode == ENOENT || errnoCode == EBADF {
            continue
          }
        }
        switch Int16(event.filter) {
        case Int16(EVFILT_USER):
          // User wakeup event - nothing to do, just unblocks
          break
        case Int16(EVFILT_TIMER):
          // Timer event - reset the corresponding timer state
          switch Int(event.ident) {
          case 1:
            // Continuous clock timer fired
            self.nextContinuousClockTimer = nil
          case 2:
            // Suspending clock timer fired
            self.nextSuspendingClockTimer = nil
          default:
            fatalError("Unknown timer identifier in kqueue event: \(event.ident)")
          }
        default:
          fatalError("Unknown filter type in kqueue event: \(event.filter)")
        }
      }
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
      if let nextContinuousClockTimer = self.nextContinuousClockTimer {
        // Only set timer if new deadline is earlier
        shouldSetTimer = continuousClockInstant < nextContinuousClockTimer
      } else {
        shouldSetTimer = true
      }

      if shouldSetTimer {
        let duration = ContinuousClock.now.duration(
          to: continuousClockInstant
        )
        let nanoseconds =
          Int(duration.components.seconds) * 1_000_000_000 + Int(duration.components.attoseconds / 1_000_000_000)
        self.pendingChanges.append(Self.timerEvent(ident: 1, nanoseconds: nanoseconds))
        self.nextContinuousClockTimer = continuousClockInstant
      }
    }

    // Set up suspending clock timer (ident = 2)
    if let suspendingClockInstant {
      let shouldSetTimer: Bool
      if let nextSuspendingClockTimer = self.nextSuspendingClockTimer {
        // Only set timer if new deadline is earlier
        shouldSetTimer = suspendingClockInstant < nextSuspendingClockTimer
      } else {
        shouldSetTimer = true
      }

      if shouldSetTimer {
        let duration = SuspendingClock.now.duration(
          to: suspendingClockInstant
        )
        let nanoseconds =
          Int(duration.components.seconds) * 1_000_000_000 + Int(duration.components.attoseconds / 1_000_000_000)
        self.pendingChanges.append(Self.timerEvent(ident: 2, nanoseconds: nanoseconds))
        self.nextSuspendingClockTimer = suspendingClockInstant
      }
    }
  }

  /// The change that arms a kqueue timer for the given instant.
  private static func timerEvent(ident: Int, nanoseconds: Int) -> Darwin.kevent {
    var event = Darwin.kevent()
    event.ident = UInt(ident)
    event.filter = Int16(EVFILT_TIMER)
    event.flags = UInt16(EV_ADD | EV_ENABLE | EV_ONESHOT)
    event.fflags = UInt32(NOTE_NSECONDS)
    event.data = nanoseconds
    event.udata = nil
    return event
  }

  /// Wakes up a backend from any thread.
  ///
  /// - Parameter handle: The handle of the backend to wake up.
  static func wakeup(_ handle: WakeupHandle) throws {
    var event = Darwin.kevent()
    event.ident = 0
    event.filter = Int16(EVFILT_USER)
    event.fflags = UInt32(NOTE_TRIGGER | NOTE_FFNOP)
    event.data = 0
    event.udata = nil
    event.flags = 0
    try withUnsafeMutablePointer(to: &event) { ptr in
      try Self.kqueueApplyEventChangeSet(
        kqueueFD: handle.kqueueFD,
        keventBuffer: UnsafeMutableBufferPointer(start: ptr, count: 1)
      )
    }
  }

}

#if ExperimentalIO
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension KQueueReadinessBackend: IOBackend {
  // TODO: Implement IO operations
  static func attempt(_ operation: IOOperation) -> Result<Int, IOError>? {
    fatalError("No support for IO operations")
  }

  mutating func submit(_ operation: IOOperation, id: IOOperationID) {
    fatalError("No support for IO operations")
  }

  mutating func cancel(_ id: IOOperationID) {
    fatalError("No support for IO operations")
  }

  mutating func wait(
    strategy: IOWaitStrategy,
    completions: inout [(IOOperationID, Result<Int, IOError>)]
  ) throws {
    // Waiting is how the executor blocks whether or not it has I/O in flight, so it works already. Nothing can
    // be submitted yet, so there is never a result to report.
    try self.whenReady(strategy: strategy)
  }
}
#else
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension KQueueReadinessBackend: IOBackend {
  mutating func wait(strategy: IOWaitStrategy) throws {
    try self.whenReady(strategy: strategy)
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
      try body(x)
    }
  }
}
#endif
