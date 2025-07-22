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
#elseif os(Windows)
import ucrt
import WinSDK
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#else
#error("The concurrency lock module was unable to identify your C library.")
#endif

final class ConditionVariable<Value: ~Copyable> {
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
    self.state = state
    #if os(Windows)
    InitializeSRWLock(lock)
    InitializeConditionVariable(condition)
    #else
    pthread_mutex_init(lock, nil)
    pthread_cond_init(condition, nil)
    #endif
  }

  private func _lock() {
    #if os(Windows)
    AcquireSRWLockExclusive(lock)
    #else
    pthread_mutex_lock(lock)
    #endif
  }

  private func _unlock() {
    #if os(Windows)
    ReleaseSRWLockExclusive(lock)
    #else
    pthread_mutex_unlock(lock)
    #endif
  }

  private func _signal() {
    #if os(Windows)
    WakeConditionVariable(condition)
    #else
    pthread_cond_signal(condition)
    #endif
  }

  private func _signalAll() {
    #if os(Windows)
    WakeAllConditionVariable(condition)
    #else
    pthread_cond_broadcast(condition)
    #endif
  }

  private func _wait() {
    #if os(Windows)
    SleepConditionVariableSRW(condition, lock, INFINITE, 0)
    #else
    pthread_cond_wait(condition, lock)
    #endif
  }

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
    return try block(&state)
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
    return try block(&state)
  }

  func wait<Return, Failure: Error>(
    block: (inout sending Value) throws(Failure) -> Return
  ) throws(Failure) -> Return {
    try self.wait(when: { _ in true }, block: block)
  }

  func wait<Return, Failure: Error>(
    when: (inout sending Value) -> Bool,
    block: (inout sending Value) throws(Failure) -> Return
  ) throws(Failure) -> Return {
    self._lock()
    defer {
      self._unlock()
    }
    while true {
      if when(&state) {
        break
      }
      self._wait()
    }
    return try block(&state)
  }
}
