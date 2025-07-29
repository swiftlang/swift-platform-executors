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

struct Thread: ~Copyable, @unchecked Sendable {
  internal typealias ThreadBoxValue = (body: () -> Void, name: String?)
  internal typealias ThreadBox = Box<ThreadBoxValue>

  private let desiredName: String?

  /// The thread handle used by this instance.
  private var handle: PThread.ThreadHandle?

  /// Indicates wether the thread must be joined to ensure no thread leaks.
  private let mustBeJoined: Bool

  /// Create a new instance
  internal init(
    handle: PThread.ThreadHandle,
    desiredName: String?,
    mustBeJoined: Bool
  ) {
    self.handle = handle
    self.desiredName = desiredName
    self.mustBeJoined = mustBeJoined
  }

  /// Get current name of the `Thread` or `nil` if not set.
  var currentName: String? {
    guard let handle else {
      return nil
    }
    return PThread.threadName(handle)
  }

  /// Spawns and runs some task in a `Thread`.
  ///
  /// - arguments:
  ///     - name: The name of the `Thread` or `nil` if no specific name should be set.
  ///     - body: The function to execute within the spawned `Thread`.
  /// - returns: The spawned `Thread` instance.
  static func spawnAndRun(
    name: String? = nil,
    body: @escaping () -> Void
  ) -> Thread {
    var handle: PThread.ThreadHandle? = nil

    // Store everything we want to pass into the c function in a Box so we
    // can hand-over the reference.
    let tuple: ThreadBoxValue = (body: body, name: name)
    let box = ThreadBox(tuple)

    PThread.run(handle: &handle, args: box)
    return Thread(handle: handle!, desiredName: name, mustBeJoined: true)
  }

  /// Returns the current running `Thread`.
  static var current: Thread {
    let handle = PThread.currentThread
    return Thread(handle: handle, desiredName: nil, mustBeJoined: false)
  }

  func isCurrentFunc() -> Bool {
    return self.isCurrent
  }

  /// Returns `true` if the calling thread is the same as this one.
  var isCurrent: Bool {
    guard let handle else {
      return false
    }
    return PThread.isCurrentThread(handle)
  }

  /// Join the thread and wait for it to finish.
  ///
  /// This method blocks until the thread has finished executing and its resources have been cleaned up.
  /// It is safe to call this method multiple times - subsequent calls will be ignored.
  ///
  /// - Important: This method must be called to properly clean up thread resources.
  consuming func join() {
    guard let handle = self.handle.take() else {
      fatalError("PThread handle was already joined")
    }
    PThread.joinThread(handle)
  }

  deinit {
    if self.mustBeJoined {
      assert(
        self.handle == nil,
        "Thread leak! Thread released without having been joined. Call join() to properly clean up thread resources."
      )
    }
  }
}

extension Thread {
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
#endif
