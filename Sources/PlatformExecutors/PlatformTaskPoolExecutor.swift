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

/// A platform-native that distributes work across multiple threads.
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public final class PlatformTaskPoolExecutor: TaskExecutor {
  #if os(Linux) || os(Android) || os(FreeBSD)
  typealias Executor = PThreadPoolExecutor
  #elseif canImport(Darwin)
  typealias Executor = DispatchTaskPoolExecutor
  #elseif os(Windows)
  typealias Executor = Win32ThreadPoolExecutor
  #endif

  // This is implicitly unwrapped and nonisolated(unsafe) since we need create
  // the platform executor first to pass itself as the unowned task executor.
  internal nonisolated(unsafe) var executor: Executor!

  public func enqueue(_ job: consuming ExecutorJob) {
    self.executor.enqueue(job)
  }
}
