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

#if canImport(Glibc)
import Glibc
import CPlatformExecutors

/// A selector that uses epoll for eventing
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
struct EpollSelector: ~Copyable {
  /// User data supports (un)packing into an `UInt64` because epoll has a user info field that we can attach which is
  /// up to 64 bits wide. We're using all of those 64 bits, 32 for a "registration ID" and 32 for the file descriptor.
  struct UserData {
    var registrationID: UInt32
    var fileDescriptor: CInt

    init(registrationID: UInt32, fileDescriptor: CInt) {
      assert(MemoryLayout<UInt64>.size == MemoryLayout<UserData>.size)
      self.registrationID = registrationID
      self.fileDescriptor = fileDescriptor
    }

    init(rawValue: UInt64) {
      let unpacked = IntegerBitPacking.unpackUInt32CInt(rawValue)
      self = .init(registrationID: unpacked.0, fileDescriptor: unpacked.1)
    }
  }

  /// The selector file descriptor.
  fileprivate var selectorFD: CInt
  /// The event file descriptor to wake the thread when a new job is enqueued.
  fileprivate let eventFD: CInt
  /// The monotonic timer file descriptor to back the suspending clock.
  fileprivate let monotonicTimerFD: CInt
  /// The boottime timer file descriptor to back the suspending clock.
  fileprivate let boottimeTimerFD: CInt
  /// The next continuous clock timer to avoid re-arming the timer if possible.
  fileprivate var nextMonotonicClockTimer: ContinuousClock.Instant?
  /// The next suspending clock timer to avoid re-arming the timer if possible.
  fileprivate var nextBoottimelockTimer: SuspendingClock.Instant?

  init() throws {
    // We try! all of these since if the creation fails there is nothing we can do to recover.
    self.selectorFD = try! Epoll.epoll_create(size: 128)
    self.eventFD = try! EventFileDescriptor.makeEventFileDescriptor(
      initval: 0,
      flags: Int32(EventFileDescriptor.EFD_CLOEXEC | EventFileDescriptor.EFD_NONBLOCK)
    )
    self.monotonicTimerFD = try! TimerFileDescriptor.timerfd_create(
      clockId: CLOCK_MONOTONIC,
      flags: Int32(TimerFileDescriptor.TFD_CLOEXEC | TimerFileDescriptor.TFD_NONBLOCK)
    )
    self.boottimeTimerFD = try! TimerFileDescriptor.timerfd_create(
      clockId: CLOCK_BOOTTIME,
      flags: Int32(TimerFileDescriptor.TFD_CLOEXEC | TimerFileDescriptor.TFD_NONBLOCK)
    )

    var ev = Epoll.epoll_event()
    ev.events = Epoll.EPOLLERR | Epoll.EPOLLHUP | Epoll.EPOLLIN
    ev.data.u64 = UInt64(
      UserData(
        registrationID: .max,
        fileDescriptor: self.eventFD
      )
    )
    try Epoll.epoll_ctl(
      epfd: self.selectorFD,
      op: Epoll.EPOLL_CTL_ADD,
      fd: self.eventFD,
      event: &ev
    )

    var monotonicTimerev = Epoll.epoll_event()
    monotonicTimerev.events = Epoll.EPOLLIN | Epoll.EPOLLERR | Epoll.EPOLLRDHUP
    monotonicTimerev.data.u64 = UInt64(
      UserData(
        registrationID: .max,
        fileDescriptor: self.monotonicTimerFD
      )
    )
    try Epoll.epoll_ctl(
      epfd: self.selectorFD,
      op: Epoll.EPOLL_CTL_ADD,
      fd: self.monotonicTimerFD,
      event: &monotonicTimerev
    )

    var boottimeTimerev = Epoll.epoll_event()
    boottimeTimerev.events = Epoll.EPOLLIN | Epoll.EPOLLERR | Epoll.EPOLLRDHUP
    boottimeTimerev.data.u64 = UInt64(
      UserData(
        registrationID: .max,
        fileDescriptor: self.boottimeTimerFD
      )
    )
    try Epoll.epoll_ctl(
      epfd: self.selectorFD,
      op: Epoll.EPOLL_CTL_ADD,
      fd: self.boottimeTimerFD,
      event: &boottimeTimerev
    )
  }

  deinit {
    // We try! all of the closes because close can only fail in the following ways:
    // - EINTR, which we eat in close
    // - EIO, which can only happen for on-disk files
    // - EBADF, which can't happen here because we would crash as EBADF is marked unacceptable
    // Therefore, we assert here that close will always succeed and if not, that's a bug we need to know
    // about.
    try! close(descriptor: self.boottimeTimerFD)
    try! close(descriptor: self.monotonicTimerFD)
    try! close(descriptor: self.eventFD)
    try! close(descriptor: self.selectorFD)
  }

  /// Blocks until the wakeup is called.
  mutating func whenReady(
    strategy: SelectorStrategy
  ) throws {
    // Right now we only handle three events at most: EventFD and two TimerFDs
    let maxEvents = 3

    try withUnsafeTemporaryAllocation(of: Epoll.epoll_event.self, capacity: maxEvents) { eventsPointer in
      let readyEvents: Int
      switch strategy {
      case .now:
        readyEvents = Int(
          try Epoll.epoll_wait(
            epfd: self.selectorFD,
            events: eventsPointer.baseAddress!,
            maxevents: Int32(maxEvents),
            timeout: 0
          )
        )
      case .blockUntilTimeout(let continuousClockInstant, let suspendingClockInstant):
        // The continuous clock maps to the boottime clock
        func setTimer(instant: ContinuousClock.Instant) throws {
          var ts = itimerspec()
          ts.it_value = timespec(duration: ContinuousClock.now.duration(to: instant))
          try TimerFileDescriptor.timerfd_settime(fd: self.boottimeTimerFD, flags: 0, newValue: &ts, oldValue: nil)
        }
        // The suspending clock maps to the monotonic clock
        func setTimer(instant: SuspendingClock.Instant) throws {
          var ts = itimerspec()
          ts.it_value = timespec(duration: SuspendingClock.now.duration(to: instant))
          try TimerFileDescriptor.timerfd_settime(fd: self.monotonicTimerFD, flags: 0, newValue: &ts, oldValue: nil)
        }
        // Only call timerfd_settime if we're not already scheduled one that will cover it.
        if let continuousClockInstant {
          if let nextMonotonicClockTimer = self.nextMonotonicClockTimer {
            if continuousClockInstant < nextMonotonicClockTimer {
              try setTimer(instant: continuousClockInstant)
            }
          } else {
            try setTimer(instant: continuousClockInstant)
          }
        }

        // Only call timerfd_settime if we're not already scheduled one that will cover it.
        if let suspendingClockInstant {
          if let nextBoottimelockTimer = self.nextBoottimelockTimer {
            if suspendingClockInstant < nextBoottimelockTimer {
              try setTimer(instant: suspendingClockInstant)
            }
          } else {
            try setTimer(instant: suspendingClockInstant)
          }
        }
        fallthrough

      case .block:
        readyEvents = Int(
          try Epoll.epoll_wait(
            epfd: self.selectorFD,
            events: eventsPointer.baseAddress!,
            maxevents: Int32(maxEvents),
            timeout: -1  // Specifying -1 blocks until a file descriptor becomes ready
          )
        )
      }

      for i in 0..<readyEvents {
        let ev = eventsPointer[i]
        let epollUserData = UserData(rawValue: ev.data.u64)
        let fd = epollUserData.fileDescriptor
        _ = epollUserData.registrationID
        switch fd {
        case self.eventFD:
          // Consume event
          var val = EventFileDescriptor.eventfd_t()
          _ = try EventFileDescriptor.eventfd_read(fd: self.eventFD, value: &val)
        case self.monotonicTimerFD:
          // Consume event
          var val: UInt64 = 0
          // We are not interested in the result
          _ = try! TimerFileDescriptor.timerfd_read(
            descriptor: self.monotonicTimerFD,
            pointer: &val,
            size: MemoryLayout.size(ofValue: val)
          )

          // Processed the earliest set timer so reset it.
          self.nextMonotonicClockTimer = nil
        case self.boottimeTimerFD:
          // Consume event
          var val: UInt64 = 0
          // We are not interested in the result
          _ = try! TimerFileDescriptor.timerfd_read(
            descriptor: self.boottimeTimerFD,
            pointer: &val,
            size: MemoryLayout.size(ofValue: val)
          )

          // Processed the earliest set timer so reset it.
          self.nextBoottimelockTimer = nil
        default:
          fatalError("Unknown file descriptor in epoll event")
        }
      }
    }
  }

  /// Wakes up the selector.
  func wakeup() throws {
    _ = try EventFileDescriptor.eventfd_write(fd: self.eventFD, value: 1)
  }

  @inline(never)
  internal static func eventfd_write(fd: CInt, value: UInt64) throws -> CInt {
    return try retryingSyscall(blocking: false) {
      CPlatformExecutors.eventfd_write(fd, value)
    }.result
  }
}

internal enum Epoll {
  internal typealias epoll_event = CPlatformExecutors.epoll_event

  internal static let EPOLL_CTL_ADD: CInt = numericCast(CPlatformExecutors.EPOLL_CTL_ADD)
  internal static let EPOLL_CTL_MOD: CInt = numericCast(CPlatformExecutors.EPOLL_CTL_MOD)
  internal static let EPOLL_CTL_DEL: CInt = numericCast(CPlatformExecutors.EPOLL_CTL_DEL)

  #if os(Android)
  internal static let EPOLLIN: CUnsignedInt = 1  //numericCast(EPOLLIN)
  internal static let EPOLLOUT: CUnsignedInt = 4  //numericCast(EPOLLOUT)
  internal static let EPOLLERR: CUnsignedInt = 8  // numericCast(EPOLLERR)
  internal static let EPOLLRDHUP: CUnsignedInt = 8192  //numericCast(EPOLLRDHUP)
  internal static let EPOLLHUP: CUnsignedInt = 16  //numericCast(EPOLLHUP)
  internal static let EPOLLET: CUnsignedInt = 2_147_483_648  //numericCast(EPOLLET)
  #elseif canImport(Musl)
  internal static let EPOLLIN: CUnsignedInt = numericCast(CPlatformExecutors.EPOLLIN)
  internal static let EPOLLOUT: CUnsignedInt = numericCast(CPlatformExecutors.EPOLLOUT)
  internal static let EPOLLERR: CUnsignedInt = numericCast(CPlatformExecutors.EPOLLERR)
  internal static let EPOLLRDHUP: CUnsignedInt = numericCast(CPlatformExecutors.EPOLLRDHUP)
  internal static let EPOLLHUP: CUnsignedInt = numericCast(CPlatformExecutors.EPOLLHUP)
  internal static let EPOLLET: CUnsignedInt = numericCast(CPlatformExecutors.EPOLLET)
  #else
  internal static let EPOLLIN: CUnsignedInt = numericCast(CPlatformExecutors.EPOLLIN.rawValue)
  internal static let EPOLLOUT: CUnsignedInt = numericCast(CPlatformExecutors.EPOLLOUT.rawValue)
  internal static let EPOLLERR: CUnsignedInt = numericCast(CPlatformExecutors.EPOLLERR.rawValue)
  internal static let EPOLLRDHUP: CUnsignedInt = numericCast(CPlatformExecutors.EPOLLRDHUP.rawValue)
  internal static let EPOLLHUP: CUnsignedInt = numericCast(CPlatformExecutors.EPOLLHUP.rawValue)
  internal static let EPOLLET: CUnsignedInt = numericCast(CPlatformExecutors.EPOLLET.rawValue)
  #endif

  internal static let ENOENT: CUnsignedInt = numericCast(CPlatformExecutors.ENOENT)

  @inline(never)
  internal static func epoll_create(size: CInt) throws -> CInt {
    return try retryingSyscall(blocking: false) {
      CPlatformExecutors.epoll_create(size)
    }.result
  }

  @inline(never)
  @discardableResult
  internal static func epoll_ctl(
    epfd: CInt,
    op: CInt,
    fd: CInt,
    event: UnsafeMutablePointer<epoll_event>
  ) throws -> CInt {
    return try retryingSyscall(blocking: false) {
      CPlatformExecutors.epoll_ctl(epfd, op, fd, event)
    }.result
  }

  @inline(never)
  internal static func epoll_wait(
    epfd: CInt,
    events: UnsafeMutablePointer<epoll_event>,
    maxevents: CInt,
    timeout: CInt
  ) throws -> CInt {
    return try retryingSyscall(blocking: false) {
      CPlatformExecutors.epoll_wait(epfd, events, maxevents, timeout)
    }.result
  }
}

private struct EpollFilterSet: OptionSet, Equatable {
  typealias RawValue = UInt8

  let rawValue: RawValue

  static let _none = EpollFilterSet([])
  static let hangup = EpollFilterSet(rawValue: 1 << 0)
  static let readHangup = EpollFilterSet(rawValue: 1 << 1)
  static let input = EpollFilterSet(rawValue: 1 << 2)
  static let output = EpollFilterSet(rawValue: 1 << 3)
  static let error = EpollFilterSet(rawValue: 1 << 4)

  init(rawValue: RawValue) {
    self.rawValue = rawValue
  }
}

extension UInt64 {
  init(_ epollUserData: EpollSelector.UserData) {
    let fd = epollUserData.fileDescriptor
    assert(fd >= 0, "\(fd) is not a valid file descriptor")
    self = IntegerBitPacking.packUInt32CInt(epollUserData.registrationID, fd)
  }
}
#endif
