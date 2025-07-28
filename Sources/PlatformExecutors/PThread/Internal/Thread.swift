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

#if os(Linux) || os(Android) || os(FreeBSD) || canImport(Darwin)
#if os(Linux) || os(FreeBSD) || os(Android)
import CPlatformExecutors
#endif

final class Thread: @unchecked Sendable {
  internal typealias ThreadBoxValue = (body: (Thread) -> Void, name: String?)
  internal typealias ThreadBox = Box<ThreadBoxValue>

  private let desiredName: String?

  /// The thread handle used by this instance.
  private let handle: PThread.ThreadHandle

  /// Create a new instance
  ///
  /// - arguments:
  ///     - handle: The `ThreadOpsSystem.ThreadHandle` that is wrapped and used by the `Thread`.
  internal init(handle: PThread.ThreadHandle, desiredName: String?) {
    self.handle = handle
    self.desiredName = desiredName
  }

  /// Execute the given body with the `pthread_t` that is used by this `Thread` as argument.
  ///
  /// - warning: Do not escape `pthread_t` from the closure for later use.
  ///
  /// - parameters:
  ///     - body: The closure that will accept the `pthread_t`.
  /// - returns: The value returned by `body`.
  internal func withUnsafeThreadHandle<Return, Failure: Error>(
    body: (PThread.ThreadHandle) throws(Failure) -> Return
  ) throws(Failure) -> Return {
    return try body(self.handle)
  }

  /// Get current name of the `Thread` or `nil` if not set.
  var currentName: String? {
    return PThread.threadName(self.handle)
  }

  /// Spawns and runs some task in a `Thread`.
  ///
  /// - arguments:
  ///     - name: The name of the `Thread` or `nil` if no specific name should be set.
  ///     - body: The function to execute within the spawned `Thread`.
  ///     - detach: Whether to detach the thread. If the thread is not detached it must be `join`ed.
  static func spawnAndRun(
    name: String? = nil,
    body: @escaping (Thread) -> Void
  ) {
    var handle: PThread.ThreadHandle? = nil

    // Store everything we want to pass into the c function in a Box so we
    // can hand-over the reference.
    let tuple: ThreadBoxValue = (body: body, name: name)
    let box = ThreadBox(tuple)

    PThread.run(handle: &handle, args: box)
  }

  /// Returns `true` if the calling thread is the same as this one.
  var isCurrent: Bool {
    return PThread.isCurrentThread(self.handle)
  }

  /// Returns the current running `Thread`.
  static var current: Thread {
    let handle = PThread.currentThread
    return Thread(handle: handle, desiredName: nil)
  }
}

extension Thread: CustomStringConvertible {
  var description: String {
    let desiredName = self.desiredName
    let actualName = self.currentName

    switch (desiredName, actualName) {
    case (.some(let desiredName), .some(desiredName)):
      // We know the current, actual name and the desired name and they match. This is hopefully the most common
      // situation.
      return "Thread(name: \(desiredName))"
    case (.some(let desiredName), .some(let actualName)):
      // We know both names but they're not equal. That's odd but not impossible, some misbehaved library might
      // have changed the name.
      return "Thread(desiredName: \(desiredName), actualName: \(actualName))"
    case (.some(let desiredName), .none):
      // We only know the desired name and can't get the actual thread name. The OS might not be able to provide
      // the name to us.
      return "Thread(desiredName: \(desiredName))"
    case (.none, .some(let actualName)):
      // We only know the actual name. This can happen when we don't have a reference to the actually spawned
      // thread but rather ask for the current thread and then print it.
      return "Thread(actualName: \(actualName))"
    case (.none, .none):
      // We know nothing, sorry.
      return "Thread(n/a)"
    }
  }
}

extension Thread: Equatable {
  static func == (lhs: Thread, rhs: Thread) -> Bool {
    return lhs.withUnsafeThreadHandle { lhs in
      rhs.withUnsafeThreadHandle { rhs in
        PThread.compareThreads(lhs, rhs)
      }
    }
  }
}
#endif
