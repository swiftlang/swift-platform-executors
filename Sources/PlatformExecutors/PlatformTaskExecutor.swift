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

/// A platform-native task executor.
@available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
public final class PlatformTaskExecutor: TaskExecutor {
  #if os(Linux) || os(Android) || os(FreeBSD)
  typealias Executor = PThreadTaskExecutor
  #elseif canImport(Darwin)
  typealias Executor = DispatchTaskExecutor
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
