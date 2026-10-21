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
#if ExperimentalIO
internal import BasicContainers
#endif

/// An I/O mechanism that uses epoll for eventing.
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
@safe
struct EpollReadinessBackend: ~Copyable {
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

  /// A handle that other threads use to wake this backend up.
  struct WakeupHandle: Sendable {
    /// The event file descriptor never changes so we can use it to wakeup the selector from any thread.
    fileprivate let eventFD: CInt
  }

  /// The file descriptor of the epoll instance.
  fileprivate var epollFD: CInt
  /// The event file descriptor to wake the thread when a new job is enqueued.
  fileprivate let eventFD: CInt
  /// The monotonic timer file descriptor to back the suspending clock.
  fileprivate let monotonicTimerFD: CInt
  /// The boottime timer file descriptor to back the continuous clock.
  fileprivate let boottimeTimerFD: CInt
  /// The deadline that the boottime timer is armed for, to avoid re-arming it for a later one.
  fileprivate var armedContinuousClockDeadline: ContinuousClock.Instant?
  /// The deadline that the monotonic timer is armed for, to avoid re-arming it for a later one.
  fileprivate var armedSuspendingClockDeadline: SuspendingClock.Instant?

  #if ExperimentalIO
  /// The operations that are waiting for their file descriptor to become ready.
  private var operations = ReadinessOperations()

  /// The events buffer.
  private var events = unsafe UniqueArray<Epoll.epoll_event>(
    minimumCapacity: IOOperation.reservedCapacity
  )
  #endif

  /// A handle that other threads use to wake this backend up.
  var wakeupHandle: WakeupHandle {
    WakeupHandle(eventFD: self.eventFD)
  }

  init() throws {
    // We try! all of these since if the creation fails there is nothing we can do to recover.
    self.epollFD = try! Epoll.epoll_create(size: 128)
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

    var ev = unsafe Epoll.epoll_event()
    unsafe ev.events = Epoll.EPOLLERR | Epoll.EPOLLHUP | Epoll.EPOLLIN
    unsafe ev.data.u64 = UInt64(
      UserData(
        registrationID: .max,
        fileDescriptor: self.eventFD
      )
    )
    try unsafe Epoll.epoll_ctl(
      epfd: self.epollFD,
      op: Epoll.EPOLL_CTL_ADD,
      fd: self.eventFD,
      event: &ev
    )

    var monotonicTimerev = unsafe Epoll.epoll_event()
    unsafe monotonicTimerev.events = Epoll.EPOLLIN | Epoll.EPOLLERR | Epoll.EPOLLRDHUP
    unsafe monotonicTimerev.data.u64 = UInt64(
      UserData(
        registrationID: .max,
        fileDescriptor: self.monotonicTimerFD
      )
    )
    try unsafe Epoll.epoll_ctl(
      epfd: self.epollFD,
      op: Epoll.EPOLL_CTL_ADD,
      fd: self.monotonicTimerFD,
      event: &monotonicTimerev
    )

    var boottimeTimerev = unsafe Epoll.epoll_event()
    unsafe boottimeTimerev.events = Epoll.EPOLLIN | Epoll.EPOLLERR | Epoll.EPOLLRDHUP
    unsafe boottimeTimerev.data.u64 = UInt64(
      UserData(
        registrationID: .max,
        fileDescriptor: self.boottimeTimerFD
      )
    )
    try unsafe Epoll.epoll_ctl(
      epfd: self.epollFD,
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
    try! close(descriptor: self.epollFD)
  }

  /// Blocks until a registered file descriptor became ready, a timer fired or the wakeup was called.
  ///
  /// The events are handed back rather than reported through a closure: handling one mutates this backend,
  /// which would overlap the access to `self` that this method holds while it runs. Each event is passed to
  /// ``process(_:)`` once this has returned.
  ///
  /// - Parameters:
  ///   - strategy: The strategy to use for blocking.
  /// Returns the timeout of `epoll_wait` for the strategy, arming the timers that wake the wait up.
  private mutating func prepareWait(strategy: IOWaitStrategy) throws -> CInt {
    let timeout: CInt
    switch strategy {
    case .now:
      timeout = 0
    case .blockUntilTimeout(let continuousClockInstant, let suspendingClockInstant):
      var hasDeadlinePassed = false
      // The continuous clock maps to the boottime clock
      if let continuousClockInstant {
        let remaining = ContinuousClock.now.duration(to: continuousClockInstant)
        if remaining <= .zero {
          hasDeadlinePassed = true
        } else if self.armedContinuousClockDeadline.map({ continuousClockInstant < $0 }) ?? true {
          try Self.arm(self.boottimeTimerFD, after: remaining)
          self.armedContinuousClockDeadline = continuousClockInstant
        }
      }
      // The suspending clock maps to the monotonic clock
      if let suspendingClockInstant {
        let remaining = SuspendingClock.now.duration(to: suspendingClockInstant)
        if remaining <= .zero {
          hasDeadlinePassed = true
        } else if self.armedSuspendingClockDeadline.map({ suspendingClockInstant < $0 }) ?? true {
          try Self.arm(self.monotonicTimerFD, after: remaining)
          self.armedSuspendingClockDeadline = suspendingClockInstant
        }
      }
      // The timers wake us up, so we can block until a file descriptor becomes ready.
      timeout = hasDeadlinePassed ? 0 : -1
    case .block:
      // Specifying -1 blocks until a file descriptor becomes ready
      timeout = -1
    }
    return timeout
  }

  /// Arms a timer to fire once after the given positive duration.
  private static func arm(_ timerFD: CInt, after duration: Duration) throws {
    var ts = itimerspec()
    // A timespec has nanosecond precision, so a duration below that
    // would round down to zero, which disarms the timer.
    ts.it_value = timespec(duration: max(duration, .nanoseconds(1)))
    try unsafe TimerFileDescriptor.timerfd_settime(fd: timerFD, flags: 0, newValue: &ts, oldValue: nil)
  }

  /// Waits for events and writes them into the given output span.
  private static func waitForEvents(
    epollFD: CInt,
    timeout: CInt,
    into events: inout OutputSpan<Epoll.epoll_event>
  ) throws {
    try unsafe events.withUnsafeMutableBufferPointer { buffer, initializedCount in
      assert(initializedCount == 0, "The events can only be written into an empty buffer")
      initializedCount = unsafe Int(
        try Epoll.epoll_wait(
          epfd: epollFD,
          events: buffer.baseAddress!,
          maxevents: CInt(buffer.count),
          timeout: timeout
        )
      )
    }
  }

  /// Processes one event that ``waitForEvents(strategy:into:)`` handed back.
  ///
  /// - Parameter ev: The event to process.
  /// - Returns: The readiness of a file descriptor that an operation waits on, or `nil` if the event was one of
  ///   this backend's own.
  private mutating func process(_ ev: Epoll.epoll_event) throws -> ReadinessEvent? {
    let epollUserData = unsafe UserData(rawValue: ev.data.u64)
    let fd = epollUserData.fileDescriptor
    _ = epollUserData.registrationID
    switch fd {
    case self.eventFD:
      // Consume event
      var val = EventFileDescriptor.eventfd_t()
      _ = try unsafe EventFileDescriptor.eventfd_read(fd: self.eventFD, value: &val)
    case self.monotonicTimerFD:
      // Consume event
      var val: UInt64 = 0
      // We are not interested in the result
      _ = try! unsafe TimerFileDescriptor.timerfd_read(
        descriptor: self.monotonicTimerFD,
        pointer: &val,
        size: MemoryLayout.size(ofValue: val)
      )

      // The timer fired so it is not armed anymore.
      self.armedSuspendingClockDeadline = nil
    case self.boottimeTimerFD:
      // Consume event
      var val: UInt64 = 0
      // We are not interested in the result
      _ = try! unsafe TimerFileDescriptor.timerfd_read(
        descriptor: self.boottimeTimerFD,
        pointer: &val,
        size: MemoryLayout.size(ofValue: val)
      )

      // The timer fired so it is not armed anymore.
      self.armedContinuousClockDeadline = nil
    default:
      return unsafe ReadinessEvent(
        registrationID: epollUserData.registrationID,
        fileDescriptor: fd,
        // `EPOLLRDHUP` is reported alongside readiness and the operation that
        // follows surfaces the end of the stream, so we treat it as being ready.
        isReadable: ev.events & (Epoll.EPOLLIN | Epoll.EPOLLRDHUP) != 0,
        isWritable: ev.events & Epoll.EPOLLOUT != 0,
        isError: ev.events & (Epoll.EPOLLERR | Epoll.EPOLLHUP) != 0
      )
    }
    return nil
  }

  /// The maximum number of events that are processed in a single tick.
  private static var maxEvents: Int { 64 }

  #if ExperimentalIO
  /// Arms the interest that the pending operations of a file descriptor need.
  ///
  /// The registrations are one-shot, so epoll disables them as soon as they produced an event and an
  /// operation that has to wait again is armed again.
  // TODO: Register every file descriptor once, edge-triggered for both directions
  // (`EPOLLET`, and `EV_CLEAR` on kqueue), and cache its readiness in
  // `ReadinessOperations`, so that operations in the steady state need no
  // `epoll_ctl` at all.
  private mutating func arm(_ registration: ReadinessOperations.Registration) {
    var events = Epoll.EPOLLONESHOT | Epoll.EPOLLERR | Epoll.EPOLLHUP
    if registration.interest.contains(.read) {
      events |= Epoll.EPOLLIN | Epoll.EPOLLRDHUP
    }
    if registration.interest.contains(.write) {
      events |= Epoll.EPOLLOUT
    }

    var event = unsafe Epoll.epoll_event()
    unsafe event.events = events
    unsafe event.data.u64 = UInt64(
      UserData(
        registrationID: registration.registrationID,
        fileDescriptor: registration.fileDescriptor
      )
    )

    // epoll wants a file descriptor to be added before its interest can be
    // changed, but whether it is in the set is not something we can track.
    // Modifying first and adding only when epoll says it does not know the file
    // descriptor asks the kernel instead, which is always right and costs the
    // extra syscall only on the first operation of a file descriptor.
    do {
      try unsafe Epoll.epoll_ctl(
        epfd: self.epollFD,
        op: Epoll.EPOLL_CTL_MOD,
        fd: registration.fileDescriptor,
        event: &event
      )
    } catch let error where error.errnoCode == ENOENT {
      do {
        try unsafe Epoll.epoll_ctl(
          epfd: self.epollFD,
          op: Epoll.EPOLL_CTL_ADD,
          fd: registration.fileDescriptor,
          event: &event
        )
      } catch {
        self.failOperations(on: registration.fileDescriptor, with: error)
      }
    } catch {
      self.failOperations(on: registration.fileDescriptor, with: error)
    }
  }

  /// Fails every operation waiting on a file descriptor that could not be armed.
  private mutating func failOperations(on fileDescriptor: CInt, with error: SyscallError) {
    self.operations.failPendingOperations(on: fileDescriptor, with: IOError(error))
  }
  #endif

  /// Wakes up a backend from any thread.
  ///
  /// - Parameter handle: The handle of the backend to wake up.
  static func wakeup(_ handle: WakeupHandle) throws {
    _ = try EventFileDescriptor.eventfd_write(fd: handle.eventFD, value: 1)
  }

  @inline(never)
  internal static func eventfd_write(fd: CInt, value: UInt64) throws -> CInt {
    return try retryingSyscall(blocking: false) {
      CPlatformExecutors.eventfd_write(fd, value)
    }.result
  }
}

#if ExperimentalIO
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension EpollReadinessBackend: IOBackend {
  static func attempt(_ operation: IOOperation) -> Result<Int, IOError>? {
    unsafe ReadinessOperations.attempt(operation)
  }

  mutating func submit(_ operation: IOOperation, id: IOOperationID) {
    guard let registration = unsafe self.operations.submit(operation, id: id) else {
      return
    }
    self.arm(registration)
  }

  mutating func cancel(_ id: IOOperationID) {
    guard let registration = self.operations.cancel(id) else {
      return
    }
    self.arm(registration)
  }

  mutating func wait(
    strategy: IOWaitStrategy,
    completions: inout [(IOOperationID, Result<Int, IOError>)]
  ) throws {
    // Something may have completed without epoll since the last tick,
    // such as a cancelled operation or a close. Nothing wakes us up for
    // those, so we must not block if there are any.
    var strategy = strategy
    if self.operations.hasReadyResults {
      strategy = .now
    }

    let timeout = try self.prepareWait(strategy: strategy)
    let epollFD = self.epollFD
    unsafe self.events.removeAll()
    try unsafe self.events.edit { events in
      try unsafe Self.waitForEvents(epollFD: epollFD, timeout: timeout, into: &events)
    }

    for index in unsafe self.events.indices {
      // The event is copied out, since processing it mutates the backend.
      let event = unsafe self.events[index]
      guard let readiness = try unsafe self.process(event),
        let registration = self.operations.handle(readiness)
      else {
        continue
      }
      self.arm(registration)
    }

    // The results are handed over last, once everything is armed.
    self.operations.takeReadyResults(into: &completions)
  }
}
#else
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension EpollReadinessBackend: IOBackend {
  mutating func wait(strategy: IOWaitStrategy) throws {
    let timeout = try self.prepareWait(strategy: strategy)
    let epollFD = self.epollFD
    try unsafe withTemporaryAllocation(of: Epoll.epoll_event.self, capacity: Self.maxEvents) { events in
      try unsafe Self.waitForEvents(epollFD: epollFD, timeout: timeout, into: &events)

      // Process the events.
      for index in unsafe events.indices {
        _ = try unsafe self.process(events[index])
      }
    }
  }
}
#endif

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
  internal static let EPOLLONESHOT: CUnsignedInt = 1_073_741_824  //numericCast(EPOLLONESHOT)
  #elseif canImport(Musl)
  internal static let EPOLLIN: CUnsignedInt = numericCast(CPlatformExecutors.EPOLLIN)
  internal static let EPOLLOUT: CUnsignedInt = numericCast(CPlatformExecutors.EPOLLOUT)
  internal static let EPOLLERR: CUnsignedInt = numericCast(CPlatformExecutors.EPOLLERR)
  internal static let EPOLLRDHUP: CUnsignedInt = numericCast(CPlatformExecutors.EPOLLRDHUP)
  internal static let EPOLLHUP: CUnsignedInt = numericCast(CPlatformExecutors.EPOLLHUP)
  internal static let EPOLLET: CUnsignedInt = numericCast(CPlatformExecutors.EPOLLET)
  internal static let EPOLLONESHOT: CUnsignedInt = numericCast(CPlatformExecutors.EPOLLONESHOT)
  #else
  internal static let EPOLLIN: CUnsignedInt = numericCast(CPlatformExecutors.EPOLLIN.rawValue)
  internal static let EPOLLOUT: CUnsignedInt = numericCast(CPlatformExecutors.EPOLLOUT.rawValue)
  internal static let EPOLLERR: CUnsignedInt = numericCast(CPlatformExecutors.EPOLLERR.rawValue)
  internal static let EPOLLRDHUP: CUnsignedInt = numericCast(CPlatformExecutors.EPOLLRDHUP.rawValue)
  internal static let EPOLLHUP: CUnsignedInt = numericCast(CPlatformExecutors.EPOLLHUP.rawValue)
  internal static let EPOLLET: CUnsignedInt = numericCast(CPlatformExecutors.EPOLLET.rawValue)
  internal static let EPOLLONESHOT: CUnsignedInt = numericCast(CPlatformExecutors.EPOLLONESHOT.rawValue)
  #endif

  internal static let ENOENT: CUnsignedInt = numericCast(CPlatformExecutors.ENOENT)

  @inline(never)
  internal static func epoll_create(size: CInt) throws(SyscallError) -> CInt {
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
  ) throws(SyscallError) -> CInt {
    return try retryingSyscall(blocking: false) {
      unsafe CPlatformExecutors.epoll_ctl(epfd, op, fd, event)
    }.result
  }

  @inline(never)
  internal static func epoll_wait(
    epfd: CInt,
    events: UnsafeMutablePointer<epoll_event>,
    maxevents: CInt,
    timeout: CInt
  ) throws(SyscallError) -> CInt {
    return try retryingSyscall(blocking: false) {
      unsafe CPlatformExecutors.epoll_wait(epfd, events, maxevents, timeout)
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
  init(_ epollUserData: EpollReadinessBackend.UserData) {
    let fd = epollUserData.fileDescriptor
    assert(fd >= 0, "\(fd) is not a valid file descriptor")
    self = IntegerBitPacking.packUInt32CInt(epollUserData.registrationID, fd)
  }
}
#endif
