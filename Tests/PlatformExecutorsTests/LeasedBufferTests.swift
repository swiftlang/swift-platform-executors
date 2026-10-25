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

import Synchronization
import Testing
@_spi(ExperimentalScheduling) @_spi(ConcurrencyExecutors) @_spi(ExperimentalCustomExecutors) import _Concurrency
@_spi(ExperimentalScheduling) @_spi(ConcurrencyExecutors) @_spi(ExperimentalCustomExecutors) import PlatformExecutors

@Suite
struct LeasedBufferTests {
  @Test
  @available(anyAppleOS 27.0, *)
  func aLeaseThatIsNotReturnedTraps() async {
    await #expect(processExitsWith: .failure) {
      _ = unsafe LeasedBuffer(
        adopting: .allocate(byteCount: 16, alignment: 16),
        initializedCount: 0,
        release: { memory in unsafe memory.deallocate() }
      )
    }
  }

  @Test
  @available(anyAppleOS 27.0, *)
  func returningALeaseCallsTheReleaseClosureWithTheMemoryOnce() async {
    let released = Mutex<[Int]>([])
    let memory = UnsafeMutableRawBufferPointer.allocate(byteCount: 16, alignment: 16)
    defer { unsafe memory.deallocate() }
    let buffer = unsafe LeasedBuffer(
      adopting: memory,
      initializedCount: 3,
      release: { returned in
        released.withLock { $0.append(returned.count) }
      }
    )
    #expect(buffer.count == 3)
    #expect(buffer.capacity == 16)
    buffer.return()
    #expect(released.withLock { $0 } == [16])
  }
}
#endif
#endif
