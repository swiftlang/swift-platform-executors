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
#if os(Linux) || os(FreeBSD) || canImport(Darwin)

@_spi(ExperimentalScheduling) @_spi(ConcurrencyExecutors) @_spi(ExperimentalCustomExecutors) import _Concurrency
@_spi(ExperimentalScheduling) @_spi(ConcurrencyExecutors) @_spi(ExperimentalCustomExecutors) import PlatformExecutors

@available(anyAppleOS 27.0, *)
extension OutputRawSpan {
  /// Appends the bytes.
  mutating func append(bytes: [UInt8]) {
    for byte in bytes {
      self.append(byte)
    }
  }

  /// Copies the bytes into an array.
  func bytesArray() -> [UInt8] {
    self.bytes.withUnsafeBytes { unsafe Array($0) }
  }
}
#endif
#endif
