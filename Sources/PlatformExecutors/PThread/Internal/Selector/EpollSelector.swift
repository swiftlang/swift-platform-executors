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

#if canImport(Glibc)
import Glibc
import CPlatformExecutors

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
struct EpollSelector {
  fileprivate let myThread: Thread
  fileprivate var selectorFD: CInt
  fileprivate let eventFD: CInt

  init() throws {
    self.myThread = Thread.current
    self.selectorFD = try Epoll.epoll_create(size: 128)
    self.eventFD = try EventFileDescriptor.makeEventFileDescriptor(
      initval: 0,
      flags: Int32(EventFileDescriptor.EFD_CLOEXEC | EventFileDescriptor.EFD_NONBLOCK)
    )

    var ev = Epoll.epoll_event()
    ev.events = Epoll.EPOLLERR | Epoll.EPOLLHUP | Epoll.EPOLLIN
    try Epoll.epoll_ctl(
      epfd: self.selectorFD,
      op: Epoll.EPOLL_CTL_ADD,
      fd: self.eventFD,
      event: &ev
    )
  }

  /// Blocks until the wakeup is called.
  func whenReady(
    strategy: SelectorStrategy
  ) throws {
    assert(self.myThread == Thread.current)

    _ = try withUnsafeTemporaryAllocation(of: Epoll.epoll_event.self, capacity: 1) { bufferPointer in
      try Epoll.epoll_wait(
        epfd: self.selectorFD,
        events: bufferPointer.baseAddress!,
        maxevents: 1,
        timeout: -1  // Specifying -1 blocks until a file descriptor becomes ready
      )
    }

    // Consume event
    var val = EventFileDescriptor.eventfd_t()
    _ = try EventFileDescriptor.eventfd_read(fd: self.eventFD, value: &val)
  }

  /// Wakes up the selector.
  func wakeup() throws {
    assert(Thread.current != self.myThread)
    _ = try EventFileDescriptor.eventfd_write(fd: self.eventFD, value: 1)
  }

  @inline(never)
  internal static func eventfd_write(fd: CInt, value: UInt64) throws -> CInt {
    return try syscall(blocking: false) {
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
    return try syscall(blocking: false) {
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
    return try syscall(blocking: false) {
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
    return try syscall(blocking: false) {
      CPlatformExecutors.epoll_wait(epfd, events, maxevents, timeout)
    }.result
  }
}

private enum EventFileDescriptor {
  fileprivate static let EFD_CLOEXEC = CPlatformExecutors.EFD_CLOEXEC
  fileprivate static let EFD_NONBLOCK = CPlatformExecutors.EFD_NONBLOCK
  fileprivate typealias eventfd_t = CPlatformExecutors.eventfd_t

  @inline(never)
  fileprivate static func eventfd_read(fd: CInt, value: UnsafeMutablePointer<UInt64>) throws -> CInt {
    return try syscall(blocking: false) {
      CPlatformExecutors.eventfd_read(fd, value)
    }.result
  }

  @inline(never)
  internal static func eventfd_write(fd: CInt, value: UInt64) throws -> CInt {
    return try syscall(blocking: false) {
      CPlatformExecutors.eventfd_write(fd, value)
    }.result
  }

  @inline(never)
  fileprivate static func makeEventFileDescriptor(initval: CUnsignedInt, flags: CInt) throws -> CInt {
    return try syscall(blocking: false) {
      // Note: Please do _not_ remove the `numericCast`, this is to allow compilation in Ubuntu 14.04 and
      // other Linux distros which ship a glibc from before this commit:
      // https://sourceware.org/git/?p=glibc.git;a=commitdiff;h=69eb9a183c19e8739065e430758e4d3a2c5e4f1a
      // which changes the first argument from `CInt` to `CUnsignedInt` (from Sat, 20 Sep 2014).
      CPlatformExecutors.eventfd(numericCast(initval), flags)
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
#endif
