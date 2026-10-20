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

@_spi(ExperimentalScheduling) @_spi(ConcurrencyExecutors) @_spi(ExperimentalCustomExecutors) import _Concurrency
internal import BasicContainers

/// The jobs that wait to run on an executor
///
/// The job with the highest priority comes first, and jobs with the same priority
/// come in the order they were pushed.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
struct JobQueue: ~Copyable {
  /// A first in first out queue in a ring buffer.
  ///
  /// The `head` is the slot of the oldest job and the next `count` slots hold the other jobs, wrapping around
  /// the end of the storage. The capacity is a power of two, so `index & (capacity - 1)` is the same as
  /// `index % capacity`. An empty slot holds `nil`.
  struct Ring: ~Copyable {
    var storage = UniqueArray<ExecutorJob?>()
    var head = 0
    var count = 0

    mutating func push(_ job: consuming ExecutorJob) {
      if self.count == self.storage.count {
        self.grow()
      }
      // The first free slot comes right after the last job, wrapped around the end of the storage.
      let tail = (self.head &+ self.count) & (self.storage.count &- 1)
      self.storage[tail] = consume job
      self.count &+= 1
    }

    mutating func pop() -> ExecutorJob {
      let job = self.storage[self.head].take()!
      // The oldest job is now the next slot, wrapped around the end of the storage.
      self.head = (self.head &+ 1) & (self.storage.count &- 1)
      self.count &-= 1
      return job
    }

    private mutating func grow() {
      // Doubling keeps the capacity a power of two.
      let capacity = max(self.storage.count * 2, 16)
      var storage = UniqueArray<ExecutorJob?>(minimumCapacity: capacity)
      let mask = self.storage.count &- 1
      // The jobs move to the start of the new storage in the order they have in the queue.
      for index in 0..<self.count {
        storage.append(self.storage[(self.head &+ index) & mask].take())
      }
      for _ in self.count..<capacity {
        storage.append(nil)
      }
      self.storage = storage
      self.head = 0
    }
  }

  /// The queues, indexed by the raw value of the priority.
  private var rings: UniqueArray<Ring> = {
    var rings = UniqueArray<Ring>(minimumCapacity: 256)
    for _ in 0..<256 {
      rings.append(Ring())
    }
    return rings
  }()

  /// A bitmap with one bit for each of the 256 priorities. A set bit means that the queue of the priority
  /// has jobs.
  ///
  /// The bitmap is four 64 bit words. The bit of a priority is `priority % 64` in the word `priority / 64`, so
  /// word 0 covers the priorities 0 to 63, word 1 covers 64 to 127, and so on. Finding the highest priority
  /// that has jobs only needs the highest set bit of the highest word that is not zero.
  private var nonEmpty: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)

  /// The number of jobs in the queue.
  private(set) var count = 0

  var isEmpty: Bool {
    self.count == 0
  }

  /// Adds a job behind the jobs with the same priority.
  mutating func push(_ job: consuming ExecutorJob) {
    let priority = Int(job.priority.rawValue)
    self.rings[priority].push(job)
    self.count &+= 1
    switch priority >> 6 {
    case 0: self.nonEmpty.0 |= 1 << UInt64(priority & 63)
    case 1: self.nonEmpty.1 |= 1 << UInt64(priority & 63)
    case 2: self.nonEmpty.2 |= 1 << UInt64(priority & 63)
    default: self.nonEmpty.3 |= 1 << UInt64(priority & 63)
    }
  }

  /// Removes the job with the highest priority that was pushed first.
  mutating func pop() -> ExecutorJob? {
    // The index of the highest set bit of a word is `63 - leadingZeroBitCount`.
    // Adding the first priority of the word makes it the priority.
    let priority: Int
    if self.nonEmpty.3 != 0 {
      priority = 192 + 63 - self.nonEmpty.3.leadingZeroBitCount
    } else if self.nonEmpty.2 != 0 {
      priority = 128 + 63 - self.nonEmpty.2.leadingZeroBitCount
    } else if self.nonEmpty.1 != 0 {
      priority = 64 + 63 - self.nonEmpty.1.leadingZeroBitCount
    } else if self.nonEmpty.0 != 0 {
      priority = 63 - self.nonEmpty.0.leadingZeroBitCount
    } else {
      return nil
    }

    let job = self.rings[priority].pop()
    self.count &-= 1
    if self.rings[priority].count == 0 {
      switch priority >> 6 {
      case 0: self.nonEmpty.0 &= ~(1 << UInt64(priority & 63))
      case 1: self.nonEmpty.1 &= ~(1 << UInt64(priority & 63))
      case 2: self.nonEmpty.2 &= ~(1 << UInt64(priority & 63))
      default: self.nonEmpty.3 &= ~(1 << UInt64(priority & 63))
      }
    }
    return job
  }
}
