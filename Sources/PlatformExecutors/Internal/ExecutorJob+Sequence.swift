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

@_spi(ExperimentalScheduling) @_spi(ConcurrencyExecutors) @_spi(ExperimentalCustomExecutors) import _Concurrency

@available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
extension ExecutorJob {
  var sequenceNumber: UInt64 {
    get {
      return withUnsafeExecutorPrivateData {
        return unsafe $0.assumingMemoryBound(to: UInt64.self)[0]
      }
    }
    set {
      return withUnsafeExecutorPrivateData {
        unsafe $0.withMemoryRebound(to: UInt64.self) {
          unsafe $0[0] = newValue
        }
      }
    }
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension ExecutorJob {
  /// The address of the next job in the inbox of an executor, or zero for the last one.
  var inboxNext: UInt {
    get {
      return withUnsafeExecutorPrivateData {
        return unsafe $0.assumingMemoryBound(to: UInt.self)[1]
      }
    }
    set {
      return withUnsafeExecutorPrivateData {
        unsafe $0.withMemoryRebound(to: UInt.self) {
          unsafe $0[1] = newValue
        }
      }
    }
  }
}
