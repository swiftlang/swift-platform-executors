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

#if canImport(WinSDK)
import Testing
@_spi(ExperimentalScheduling) @_spi(ConcurrencyExecutors) @_spi(ExperimentalCustomExecutors) import _Concurrency
@_spi(ExperimentalScheduling) @_spi(ConcurrencyExecutors) @_spi(ExperimentalCustomExecutors) import PlatformExecutors

@Suite(.serialized) struct Win32ExecutorTests {
  @Test func testEventLoopExecutor() async {
    let eventLoopOK = await ExecutorFixture.test(executor: Win32EventLoopExecutor())
    #expect(eventLoopOK)
  }

  @Test func testThreadPoolExecutor() async {
    let threadPoolOK = await ExecutorFixture.test(executor: Win32ThreadPoolExecutor())
    #expect(threadPoolOK)
  }
}
#endif
