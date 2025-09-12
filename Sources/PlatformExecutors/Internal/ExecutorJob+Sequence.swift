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

@available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
extension ExecutorJob {
  var sequenceNumber: UInt64 {
    get {
      return unsafe withUnsafeExecutorPrivateData {
        return unsafe $0.assumingMemoryBound(to: UInt64.self)[0]
      }
    }
    set {
      return unsafe withUnsafeExecutorPrivateData {
        unsafe $0.withMemoryRebound(to: UInt64.self) {
          unsafe $0[0] = newValue
        }
      }
    }
  }
}
