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
internal import Synchronization

/// A task executor that distributes work across multiple `PThreadExecutor` instances.
///
/// `PThreadPoolExecutor` provides a multi-threaded execution environment by maintaining a pool of `PThreadExecutor`
/// instances and distributing jobs across them. This design enables parallel execution while leveraging the
/// optimized single-threaded executors as building blocks.
///
/// ## Usage
///
/// ```swift
/// // Create pool for parallel processing
/// let pool = PThreadPoolExecutor(name: "ProcessingPool", poolSize: 4)
///
/// await withTaskExecutorPreference(pool) {
///     // Jobs distributed across the pool
///     async let result1 = heavyComputation1()
///     async let result2 = heavyComputation2()
///     async let result3 = heavyComputation3()
///
///     return await [result1, result2, result3]
/// }
/// ```
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
public final class PThreadPoolExecutor: TaskExecutor {
  /// The pool's name.
  private let name: String
  /// The pool's executors.
  ///
  /// This is nonisolated(unsafe) and a var since we need to pass self to the individual threads which requires
  /// us to be fully initialized.
  private nonisolated(unsafe) var executors: [PThreadExecutor]!
  /// The current index for selecting the next executor to run on.
  private let index = Atomic<Int>(0)

  /// Creates a new `PThreadPoolExecutor` with the specified pool size and thread naming.
  ///
  /// This initializer creates a pool of `PThreadExecutor` instances, each with its own dedicated thread.
  ///
  /// - Parameters:
  ///   - name: The base name for the executor pool. Each thread in the pool will be named `"<name>-<index>"`
  ///     where index starts from 0.
  ///   - poolSize: The number of `PThreadExecutor` instances to create in the pool. Must be greater than 0.
  public init(
    name: String,
    poolSize: Int
  ) {
    self.name = name
    precondition(poolSize > 0, "The pool size must be positive")
    var executors = [PThreadExecutor]()
    executors.reserveCapacity(poolSize)
    for i in 0..<poolSize {
      executors.append(PThreadExecutor(name: "\(name)-\(i)", poolExecutor: self))
    }
    self.executors = executors
  }

  public func enqueue(_ job: consuming ExecutorJob) {
    self.next().enqueue(job)
  }

  private func next() -> PThreadExecutor {
    self.executors[abs(self.index.wrappingAdd(1, ordering: .relaxed).newValue % self.executors.count)]
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension PThreadPoolExecutor: CustomStringConvertible {
  public var description: String {
    "PThreadPoolExecutor(\(self.name))"
  }
}
#endif
