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

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
struct KQueueSelector: ~Copyable {
  /// The selector file descriptor.
  fileprivate var selectorFD: CInt
  /// The next continuous clock timer to avoid re-arming the timer if possible.
  fileprivate var nextContinuousClockTimer: ContinuousClock.Instant?
  /// The next suspending clock timer to avoid re-arming the timer if possible.
  fileprivate var nextSuspendingClockTimer: SuspendingClock.Instant?

  init() throws {
    self.selectorFD = try! Self.kqueue()

    var event = Darwin.kevent()
    event.ident = 0
    event.filter = Int16(EVFILT_USER)
    event.fflags = UInt32(NOTE_FFNOP)
    event.data = 0
    event.udata = nil
    event.flags = UInt16(EV_ADD | EV_ENABLE | EV_CLEAR)
    try withUnsafeMutablePointer(to: &event) { ptr in
      try Self.kqueueApplyEventChangeSet(
        selectorFD: selectorFD,
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
    try! close(descriptor: self.selectorFD)
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
    selectorFD: CInt,
    keventBuffer: UnsafeMutableBufferPointer<kevent>
  ) throws {
    guard keventBuffer.count > 0 else {
      // nothing to do
      return
    }
    do {
      try Self.kevent(
        kq: selectorFD,
        changelist: keventBuffer.baseAddress!,
        nchanges: CInt(keventBuffer.count),
        eventlist: nil,
        nevents: 0,
        timeout: nil
      )
    } catch let err as IOError {
      if err.errnoCode == EINTR {
        // See https://www.freebsd.org/cgi/man.cgi?query=kqueue&sektion=2
        // When kevent() call fails with EINTR error, all changes in the changelist have been applied.
        return
      }
      throw err
    }
  }

  private static func toKQueueTimeSpec(strategy: SelectorStrategy) -> timespec? {
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

  /// Blocks until the wakeup is called.
  mutating func whenReady(
    strategy: SelectorStrategy
  ) throws {
    // Set up timers if needed
    try self.setupTimers(strategy: strategy)

    let timespec = Self.toKQueueTimeSpec(strategy: strategy)

    // We need to handle timer events, so allocate space for events
    let maxEvents = 3  // User event + 2 timer events
    try withUnsafeTemporaryAllocation(of: Darwin.kevent.self, capacity: maxEvents) { eventsPointer in
      let readyEvents = try timespec.withUnsafeOptionalPointer { ts in
        Int(
          try Self.kevent(
            kq: self.selectorFD,
            changelist: nil,
            nchanges: 0,
            eventlist: eventsPointer.baseAddress!,
            nevents: CInt(maxEvents),
            timeout: ts
          )
        )
      }

      // Process the ready events
      for i in 0..<readyEvents {
        let event = eventsPointer[i]
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

  /// Set up kqueue timers for the given strategy
  private mutating func setupTimers(strategy: SelectorStrategy) throws {
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
        try self.setTimer(ident: 1, nanoseconds: nanoseconds)
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
        try self.setTimer(ident: 2, nanoseconds: nanoseconds)
        self.nextSuspendingClockTimer = suspendingClockInstant
      }
    }
  }

  /// Set a kqueue timer for the given instant
  private func setTimer(ident: Int, nanoseconds: Int) throws {
    var event = Darwin.kevent()
    event.ident = UInt(ident)
    event.filter = Int16(EVFILT_TIMER)
    event.flags = UInt16(EV_ADD | EV_ENABLE | EV_ONESHOT)
    event.fflags = UInt32(NOTE_NSECONDS)
    event.data = nanoseconds
    event.udata = nil

    try withUnsafeMutablePointer(to: &event) { ptr in
      try Self.kqueueApplyEventChangeSet(
        selectorFD: self.selectorFD,
        keventBuffer: UnsafeMutableBufferPointer(start: ptr, count: 1)
      )
    }
  }

  /// Wakes up the selector.
  func wakeup() throws {
    var event = Darwin.kevent()
    event.ident = 0
    event.filter = Int16(EVFILT_USER)
    event.fflags = UInt32(NOTE_TRIGGER | NOTE_FFNOP)
    event.data = 0
    event.udata = nil
    event.flags = 0
    try withUnsafeMutablePointer(to: &event) { ptr in
      try Self.kqueueApplyEventChangeSet(
        selectorFD: self.selectorFD,
        keventBuffer: UnsafeMutableBufferPointer(start: ptr, count: 1)
      )
    }
  }
}

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
