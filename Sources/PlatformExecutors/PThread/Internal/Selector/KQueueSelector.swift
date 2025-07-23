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

#if canImport(Darwin)
import Darwin

private let sysKevent = kevent

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
struct KQueueSelector {
  fileprivate var selectorFD: CInt

  init() throws {
    self.selectorFD = try Self.kqueue()

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

  @inline(never)
  fileprivate static func kqueue() throws -> CInt {
    return try syscall(blocking: false) {
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
    return try syscall(blocking: false) {
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
    case .now:
      return timespec(tv_sec: 0, tv_nsec: 0)
    }
  }

  /// Blocks until the wakeup is called.
  func whenReady(
    strategy: SelectorStrategy
  ) throws {
    let timespec = Self.toKQueueTimeSpec(strategy: strategy)
    _ = try timespec.withUnsafeOptionalPointer { ts in
      Int(
        try Self.kevent(
          kq: self.selectorFD,
          changelist: nil,
          nchanges: 0,
          eventlist: nil,
          nevents: 0,
          timeout: ts
        )
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
