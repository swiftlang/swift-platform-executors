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
#elseif os(Windows)
import ucrt
import WinSDK
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif os(WASI)
import CPlatformExecutors
import WASILibc
import wasi_pthread
#else
#error("The concurrency lock module was unable to identify your C library.")
#endif

@safe
final class ConditionVariable<Value: ~Copyable>: @unchecked Sendable {
  #if os(Windows)
  typealias LockType = SRWLOCK
  typealias ConditionVariableType = CONDITION_VARIABLE
  #elseif os(FreeBSD) || os(OpenBSD)
  typealias LockType = pthread_mutex_t?
  typealias ConditionVariableType = pthread_cond_t?
  #else
  typealias LockType = pthread_mutex_t
  typealias ConditionVariableType = pthread_cond_t
  #endif

  private nonisolated(unsafe) var state: Value
  private nonisolated(unsafe) let lock = UnsafeMutablePointer<LockType>.allocate(capacity: 1)
  private nonisolated(unsafe) let condition = UnsafeMutablePointer<ConditionVariableType>.allocate(capacity: 1)

  init(_ state: consuming sending Value) {
    unsafe self.state = state
    #if os(Windows)
    InitializeSRWLock(lock)
    InitializeConditionVariable(condition)
    #else
    unsafe pthread_mutex_init(lock, nil)
    unsafe pthread_cond_init(condition, nil)
    #endif
  }

  private func _lock() {
    #if os(Windows)
    AcquireSRWLockExclusive(lock)
    #else
    unsafe pthread_mutex_lock(lock)
    #endif
  }

  private func _unlock() {
    #if os(Windows)
    ReleaseSRWLockExclusive(lock)
    #else
    unsafe pthread_mutex_unlock(lock)
    #endif
  }

  private func _signal() {
    #if os(Windows)
    WakeConditionVariable(condition)
    #else
    unsafe pthread_cond_signal(condition)
    #endif
  }

  private func _signalAll() {
    #if os(Windows)
    WakeAllConditionVariable(condition)
    #else
    unsafe pthread_cond_broadcast(condition)
    #endif
  }

  private func _wait() {
    #if os(Windows)
    SleepConditionVariableSRW(condition, lock, INFINITE, 0)
    #else
    unsafe pthread_cond_wait(condition, lock)
    #endif
  }

  #if os(WASI)
  /// Waits at most `timeout`; true when woken, false on the timeout.
  private func _wait(timeout: Duration) -> Bool {
    var deadline = Self.realtimeDeadline(after: timeout)
    return pthread_cond_timedwait(condition, lock, &deadline) != ETIMEDOUT
  }

  /// The absolute CLOCK_REALTIME time `timeout` from now, as
  /// pthread_cond_timedwait wants it. A negative timeout is now; a timeout
  /// too far for `time_t` saturates rather than wrapping.
  private static func realtimeDeadline(after timeout: Duration) -> timespec {
    var now = timespec()
    if clock_gettime(CPlatformExecutors_CLOCK_REALTIME, &now) != 0 {
      now = timespec()
    }
    let nanosecondsPerSecond: Int128 = 1_000_000_000
    let nanoseconds = max(0, timeout.attoseconds / 1_000_000_000)
    let (seconds, remainder) = nanoseconds.quotientAndRemainder(dividingBy: nanosecondsPerSecond)
    var totalSeconds = Int128(now.tv_sec) + seconds
    var totalNanoseconds = Int128(now.tv_nsec) + remainder
    if totalNanoseconds >= nanosecondsPerSecond {
      totalNanoseconds -= nanosecondsPerSecond
      totalSeconds += 1
    }
    guard totalSeconds <= Int128(time_t.max) else {
      return timespec(tv_sec: time_t.max, tv_nsec: Int(nanosecondsPerSecond - 1))
    }
    return timespec(tv_sec: time_t(totalSeconds), tv_nsec: Int(totalNanoseconds))
  }

  /// Like `wait(when:block:)`, giving up once `timeout` has elapsed (the
  /// block then runs whether or not `when` holds).
  func wait<Return, Failure: Error>(
    until timeout: Duration,
    when: (inout sending Value) -> Bool,
    block: (inout sending Value) throws(Failure) -> Return
  ) throws(Failure) -> Return {
    self._lock()
    defer {
      self._unlock()
    }
    while !when(&state) {
      if !self._wait(timeout: timeout) {
        break
      }
    }
    return try block(&state)
  }
  #endif

  func signal<Return, Failure: Error>(
    block: (inout sending Value) throws(Failure) -> Return
  ) throws(Failure) -> Return {
    self._lock()
    defer {
      self._unlock()
    }
    defer {
      self._signal()
    }
    return try unsafe block(&state)
  }

  /// Runs the block while holding the lock, without signalling anybody.
  ///
  /// This is for changes that don't give a waiter anything to do.
  func withLock<Return: ~Copyable>(
    _ block: (inout sending Value) -> Return
  ) -> Return {
    self._lock()
    defer {
      self._unlock()
    }
    return unsafe block(&state)
  }

  /// Runs the block while holding the lock, and signals one waiter only if the
  /// block asks for it.
  ///
  /// The signal is sent after the lock is released.
  func withLockAndSignalIfNeeded<Return>(
    _ block: (inout sending Value) -> (shouldSignal: Bool, result: Return)
  ) -> Return {
    self._lock()
    let (shouldSignal, result) = unsafe block(&state)
    self._unlock()
    if shouldSignal {
      self._signal()
    }
    return result
  }

  func signalAll<Return, Failure: Error>(
    block: (inout sending Value) throws(Failure) -> Return
  ) throws(Failure) -> Return {
    self._lock()
    defer {
      self._unlock()
    }
    defer {
      self._signalAll()
    }
    return try unsafe block(&state)
  }

  func wait<Return: ~Copyable, Failure: Error>(
    block: (inout sending Value) throws(Failure) -> Return
  ) throws(Failure) -> Return {
    try self.wait(when: { _ in true }, block: block)
  }

  func wait<Return: ~Copyable, Failure: Error>(
    when: (inout sending Value) -> Bool,
    block: (inout sending Value) throws(Failure) -> Return
  ) throws(Failure) -> Return {
    self._lock()
    defer {
      self._unlock()
    }
    while true {
      if unsafe when(&state) {
        break
      }
      self._wait()
    }
    return try unsafe block(&state)
  }
}
