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

#if os(WASI)
import CPlatformExecutors
import WASILibc
import wasi_pthread

/// An I/O mechanism that uses a condition variable for eventing.
///
/// WASI has no `epoll`/`kqueue`, and the executor registers no I/O there, so
/// "wait until woken or until the next clock deadline" is a condition
/// variable: ``wakeup(_:)`` (called from any thread) raises a flag and signals;
/// ``wait(strategy:)`` waits for the flag, with a timed wait for the
/// earliest pending deadline. Spurious wakeups just re-check the flag.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
struct ConditionSelectorBackend: ~Copyable, IOBackend {
  /// A handle that other threads use to wake this backend up.
  ///
  /// This is unchecked since `ConditionVariable` guards its state with a mutex, so the reference can be
  /// shared with other threads.
  struct WakeupHandle: @unchecked Sendable {
    fileprivate let condition: ConditionVariable<Bool>
  }

  /// The wakeup flag: set by `wakeup(_:)`, consumed by `wait(strategy:)`.
  private let condition = ConditionVariable(false)

  /// A handle that other threads use to wake this backend up.
  var wakeupHandle: WakeupHandle {
    WakeupHandle(condition: self.condition)
  }

  init() throws {}

  /// Blocks until there is work to do.
  mutating func wait(strategy: IOWaitStrategy) throws {
    switch strategy {
    case .now:
      // Nothing to wait for; a wakeup that already happened is consumed.
      self.condition.signal { $0 = false }
    case .block:
      self.condition.wait(when: { $0 }, block: { $0 = false })
    case .blockUntilTimeout(let continuousClockInstant, let suspendingClockInstant):
      var timeout: Duration? = nil
      if let continuousClockInstant {
        timeout = ContinuousClock.now.duration(to: continuousClockInstant)
      }
      if let suspendingClockInstant {
        let duration = SuspendingClock.now.duration(to: suspendingClockInstant)
        timeout = timeout.map { min($0, duration) } ?? duration
      }
      guard let timeout, timeout > .zero else {
        // A deadline is already due: return so the executor pops it.
        self.condition.signal { $0 = false }
        return
      }
      self.condition.wait(until: timeout, when: { $0 }, block: { $0 = false })
    }
  }

  /// Wakes up a backend from any thread.
  ///
  /// - Parameter handle: The handle of the backend to wake up.
  static func wakeup(_ handle: WakeupHandle) throws {
    handle.condition.signal { $0 = true }
  }
}
#endif
