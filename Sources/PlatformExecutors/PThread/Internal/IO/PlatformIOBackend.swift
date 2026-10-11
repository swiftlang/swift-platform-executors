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

#if os(Linux) || os(Android) || os(FreeBSD) || canImport(Darwin) || os(WASI)
#if !canImport(Darwin) && !canImport(Glibc) && !os(WASI)
#error("Unsupported platform")
#endif

/// The I/O mechanism of an executor which is picked when the executor is created.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
enum PlatformIOBackend: ~Copyable {
  #if canImport(Darwin)
  case kqueue(KQueueReadinessBackend)
  #elseif canImport(Glibc)
  case epoll(EpollReadinessBackend)
  #if ExperimentalIOUring
  case ioUring(IOUringBackend)
  #endif
  #elseif os(WASI)
  case condition(ConditionSelectorBackend)
  #endif

  /// A handle that other threads use to wake the mechanism up and to attempt operations.
  enum WakeupHandle: Sendable {
    #if canImport(Darwin)
    case kqueue(KQueueReadinessBackend.WakeupHandle)
    #elseif canImport(Glibc)
    case epoll(EpollReadinessBackend.WakeupHandle)
    #if ExperimentalIOUring
    case ioUring(IOUringBackend.WakeupHandle)
    #endif
    #elseif os(WASI)
    case condition(ConditionSelectorBackend.WakeupHandle)
    #endif
  }

  /// Creates the mechanism that the configuration selects.
  ///
  /// - Parameter configuration: The configuration that selects the mechanism.
  init(_ configuration: PThreadIOBackend) {
    switch configuration.kind {
    case .platformDefault:
      #if canImport(Darwin)
      self = .kqueue(try! KQueueReadinessBackend())
      #elseif canImport(Glibc)
      #if ExperimentalIOUring
      do {
        self = .ioUring(try IOUringBackend())
      } catch {
        // The kernel is too old for io_uring or does not allow it, for
        // example because of a container's seccomp profile.
        self = .epoll(try! EpollReadinessBackend())
      }
      #else
      self = .epoll(try! EpollReadinessBackend())
      #endif
      #elseif os(WASI)
      self = .condition(try! ConditionSelectorBackend())
      #endif
    #if canImport(Darwin)
    case .kqueue:
      self = .kqueue(try! KQueueReadinessBackend())
    #elseif canImport(Glibc)
    case .epoll:
      self = .epoll(try! EpollReadinessBackend())
    #if ExperimentalIOUring
    case .ioUring:
      do {
        self = .ioUring(try IOUringBackend())
      } catch {
        fatalError("Creating an io_uring failed: \(error)")
      }
    #endif
    #endif
    }
  }

  /// A handle that other threads use to wake the mechanism up and to attempt operations.
  var wakeupHandle: WakeupHandle {
    switch self {
    #if canImport(Darwin)
    case .kqueue(let backend):
      return .kqueue(backend.wakeupHandle)
    #elseif canImport(Glibc)
    case .epoll(let backend):
      return .epoll(backend.wakeupHandle)
    #if ExperimentalIOUring
    case .ioUring(let backend):
      return .ioUring(backend.wakeupHandle)
    #endif
    #elseif os(WASI)
    case .condition(let backend):
      return .condition(backend.wakeupHandle)
    #endif
    }
  }

  /// Wakes up a mechanism that is waiting for work.
  ///
  /// - Note: This can be called from any thread.
  ///
  /// - Parameter handle: The handle of the mechanism to wake up.
  static func wakeup(_ handle: WakeupHandle) throws {
    switch handle {
    #if canImport(Darwin)
    case .kqueue(let handle):
      try KQueueReadinessBackend.wakeup(handle)
    #elseif canImport(Glibc)
    case .epoll(let handle):
      try EpollReadinessBackend.wakeup(handle)
    #if ExperimentalIOUring
    case .ioUring(let handle):
      try IOUringBackend.wakeup(handle)
    #endif
    #elseif os(WASI)
    case .condition(let handle):
      try ConditionSelectorBackend.wakeup(handle)
    #endif
    }
  }

  #if ExperimentalIO
  /// Performs the operation if the mechanism can perform it without waiting.
  ///
  /// - Important: This can be called from any thread.
  ///
  /// - Parameters:
  ///   - operation: The operation to perform.
  ///   - handle: The handle of the mechanism, which tells which mechanism performs the operation.
  /// - Returns: The result of the operation, or `nil` if it cannot be performed without waiting.
  static func attempt(_ operation: IOOperation, handle: WakeupHandle) -> Result<Int, IOError>? {
    switch handle {
    #if canImport(Darwin)
    case .kqueue:
      return KQueueReadinessBackend.attempt(operation)
    #elseif canImport(Glibc)
    case .epoll:
      return EpollReadinessBackend.attempt(operation)
    #if ExperimentalIOUring
    case .ioUring:
      return IOUringBackend.attempt(operation)
    #endif
    #elseif os(WASI)
    case .condition:
      return ConditionSelectorBackend.attempt(operation)
    #endif
    }
  }

  /// Submits an operation whose result is reported later.
  ///
  /// - Parameters:
  ///   - operation: The operation to submit.
  ///   - id: The identity to report the result of the operation with.
  mutating func submit(_ operation: IOOperation, id: IOOperationID) {
    switch consume self {
    #if canImport(Darwin)
    case .kqueue(var backend):
      backend.submit(operation, id: id)
      self = .kqueue(backend)
    #elseif canImport(Glibc)
    case .epoll(var backend):
      backend.submit(operation, id: id)
      self = .epoll(backend)
    #if ExperimentalIOUring
    case .ioUring(var backend):
      backend.submit(operation, id: id)
      self = .ioUring(backend)
    #endif
    #elseif os(WASI)
    case .condition(var backend):
      backend.submit(operation, id: id)
      self = .condition(backend)
    #endif
    }
  }

  /// Cancels a submitted operation, which still reports a result.
  ///
  /// - Parameter id: The identity of the operation to cancel.
  mutating func cancel(_ id: IOOperationID) {
    switch consume self {
    #if canImport(Darwin)
    case .kqueue(var backend):
      backend.cancel(id)
      self = .kqueue(backend)
    #elseif canImport(Glibc)
    case .epoll(var backend):
      backend.cancel(id)
      self = .epoll(backend)
    #if ExperimentalIOUring
    case .ioUring(var backend):
      backend.cancel(id)
      self = .ioUring(backend)
    #endif
    #elseif os(WASI)
    case .condition(var backend):
      backend.cancel(id)
      self = .condition(backend)
    #endif
    }
  }

  /// Waits for work to become available and hands over every operation that completed.
  ///
  /// - Parameters:
  ///   - strategy: How long to wait for work to become available.
  ///   - completions: The array to move the results into. It has to be empty.
  mutating func wait(
    strategy: IOWaitStrategy,
    completions: inout [(IOOperationID, Result<Int, IOError>)]
  ) throws {
    switch consume self {
    #if canImport(Darwin)
    case .kqueue(var backend):
      do {
        try backend.wait(strategy: strategy, completions: &completions)
      } catch {
        self = .kqueue(backend)
        throw error
      }
      self = .kqueue(backend)
    #elseif canImport(Glibc)
    case .epoll(var backend):
      do {
        try backend.wait(strategy: strategy, completions: &completions)
      } catch {
        self = .epoll(backend)
        throw error
      }
      self = .epoll(backend)
    #if ExperimentalIOUring
    case .ioUring(var backend):
      do {
        try backend.wait(strategy: strategy, completions: &completions)
      } catch {
        self = .ioUring(backend)
        throw error
      }
      self = .ioUring(backend)
    #endif
    #elseif os(WASI)
    case .condition(var backend):
      do {
        try backend.wait(strategy: strategy, completions: &completions)
      } catch {
        self = .condition(backend)
        throw error
      }
      self = .condition(backend)
    #endif
    }
  }
  #else
  /// Waits for work to become available.
  ///
  /// - Parameter strategy: How long to wait for work to become available.
  mutating func wait(strategy: IOWaitStrategy) throws {
    switch consume self {
    #if canImport(Darwin)
    case .kqueue(var backend):
      do {
        try backend.wait(strategy: strategy)
      } catch {
        self = .kqueue(backend)
        throw error
      }
      self = .kqueue(backend)
    #elseif canImport(Glibc)
    case .epoll(var backend):
      do {
        try backend.wait(strategy: strategy)
      } catch {
        self = .epoll(backend)
        throw error
      }
      self = .epoll(backend)
    #elseif os(WASI)
    case .condition(var backend):
      do {
        try backend.wait(strategy: strategy)
      } catch {
        self = .condition(backend)
        throw error
      }
      self = .condition(backend)
    #endif
    }
  }
  #endif
}
#endif
