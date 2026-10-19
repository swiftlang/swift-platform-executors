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

#if ExperimentalIO
#if os(Linux) || os(Android) || os(FreeBSD) || canImport(Darwin)
@_spi(SplitContinuation) import _Concurrency
internal import BasicContainers
internal import Synchronization

/// A pool of threads that run blocking syscalls for tasks that wait for them.
@available(anyAppleOS 27.0, *)
final class BlockingWorkQueue: @unchecked Sendable {
  /// An operation that waits to be run.
  private struct Entry: ~Copyable {
    /// The operation.
    var operation: IOOperation

    /// The priority of the operation, which is the one of its task and rises when that is escalated.
    var priority: TaskPriority

    /// The operation's continuation.
    var continuation: Continuation<Int, IOError>
  }

  /// Where an operation is in the order of the queued operations.
  private struct Key {
    var priority: TaskPriority
    var id: UInt64

    /// Whether the operation of the left key runs before the one of the right key.
    static func runsBefore(_ lhs: borrowing Key, _ rhs: borrowing Key) -> Bool {
      if lhs.priority != rhs.priority {
        return lhs.priority > rhs.priority
      }
      // If the priorities are equal we order by submit order.
      return lhs.id < rhs.id
    }
  }

  /// Type needed to carry out an entry and a bool from a closure since tuples don't support `~Copyable` types.
  private struct Taken: ~Copyable {
    /// The entry to run, or `nil` if the queue has none.
    var entry: Entry?

    /// Whether the pool is shutting down.
    var isStopping: Bool
  }

  private struct State: ~Copyable {
    /// The keys of the operations in the order they run in. This includes the keys of cancelled operations
    /// and the stale ones of escalated operations, which the workers skip.
    // TODO: We should check if we can avoid stale keys in the future without
    // too much overhead.
    var order = PriorityQueue<Key>(compare: Key.runsBefore)

    /// The operations that wait to be run, by identity.
    var pending = UniqueDictionary<UInt64, Entry>()

    /// Whether the executor is stopping.
    var isStopping = false

    /// The number of workers that wait for an operation. Submitting only has to wake a worker if there is one.
    var idleWorkers = 0
  }

  /// The queue's thread.
  private let state = ConditionVariable(State())

  /// The identity of the next submitted operation.
  private let nextID = Atomic<UInt64>(0)

  /// The threads of the pool, which are joined and removed by ``shutdown()``.
  private var threads: UniqueArray<Thread>

  /// Creates the pool and starts its threads.
  ///
  /// - Parameters:
  ///   - name: The base name of the threads, which are named `"<name>-<index>"`.
  ///   - threadCount: The number of threads.
  init(name: String, threadCount: Int) {
    precondition(threadCount > 0, "The pool size must be positive")
    var threads = UniqueArray<Thread>(minimumCapacity: threadCount)
    let state = self.state
    for index in 0..<threadCount {
      threads.append(
        Thread.spawnAndRun(name: "\(name)-\(index)") {
          Self.work(state)
        }
      )
    }
    self.threads = threads
  }

  /// Stops the threads once they ran everything that is queued, and joins them.
  func shutdown() {
    self.state.signalAll { $0.isStopping = true }
    while let thread = self.threads.popLast() {
      thread.join()
    }
  }

  /// Queues an operation for the next free thread.
  ///
  /// - Parameters:
  ///   - operation: The operation to run.
  ///   - priority: The priority of the operation.
  ///   - continuation: The continuation to resume with the result of the operation.
  /// - Returns: The identity of the operation, which can be used to cancel it and to escalate its priority.
  func submit(
    operation: IOOperation,
    priority: TaskPriority,
    continuation: consuming Continuation<Int, IOError>
  ) -> UInt64 {
    let id = self.nextID.wrappingAdd(1, ordering: .relaxed).newValue
    var entry = Optional(Entry(operation: operation, priority: priority, continuation: continuation))
    self.state.withLockAndSignalIfNeeded { state in
      state.order.push(Key(priority: priority, id: id))
      // The force-unwrap is safe we just need call-once closures.
      let rejected = state.pending.insertValue(entry.take()!, forKey: id)
      guard case .none = consume rejected else {
        fatalError("An operation was submitted with the identity of one that is still queued")
      }
      // A busy worker looks at the queue again once it is done, so nobody has to be woken up for it.
      return (state.idleWorkers > 0, ())
    }
    return id
  }

  /// Cancels an operation if it still waits in the queue, resuming its task with `IOError/Code/cancelled`.
  ///
  /// - Parameter id: The identity of the operation.
  func cancel(_ id: UInt64) {
    let entry = self.state.withLock { state in
      state.pending.removeValue(forKey: id)
    }
    if let entry = entry {
      entry.continuation.resume(throwing: IOError(code: .cancelled))
    }
  }

  /// Raises the priority of an operation if it still waits in the queue and has a lower priority.
  ///
  /// - Parameters:
  ///   - id: The identity of the operation.
  ///   - priority: The new priority of the operation.
  // TODO: We do not escalate the underlying thread priorities for in-progress operations.
  func escalate(_ id: UInt64, to priority: TaskPriority) {
    // This does not give any worker something to do either, since the operation was queued already.
    self.state.withLock { state in
      guard var entry = state.pending.removeValue(forKey: id) else {
        return
      }
      if priority > entry.priority {
        entry.priority = priority
        // The key of the lower priority is stale from now on.
        state.order.push(Key(priority: priority, id: id))
      }
      let rejected = state.pending.insertValue(entry, forKey: id)
      guard case .none = consume rejected else {
        fatalError("An operation was queued twice")
      }
    }
  }

  private static func work(_ state: ConditionVariable<State>) {
    while true {
      // Whether this worker is counted as idle.
      var isCountedIdle = false
      var taken = state.wait { state in
        if isCountedIdle {
          state.idleWorkers -= 1
          isCountedIdle = false
        }
        if !state.order.isEmpty || state.isStopping {
          return true
        }
        state.idleWorkers += 1
        isCountedIdle = true
        return false
      } block: { state -> Taken in
        while let key = state.order.pop() {
          // The key of a cancelled operation stays in the queue until it gets here.
          if let entry = state.pending.removeValue(forKey: key.id) {
            return Taken(entry: entry, isStopping: false)
          }
        }
        return Taken(entry: nil, isStopping: state.isStopping)
      }

      guard let entry = taken.entry.take() else {
        if taken.isStopping {
          return
        }
        continue
      }
      let result = FileSyscall.perform(entry.operation)
      entry.continuation.resume(with: result)
    }
  }
}
#endif
#endif
