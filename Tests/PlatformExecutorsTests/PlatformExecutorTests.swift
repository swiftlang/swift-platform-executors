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

#if os(Linux) || os(FreeBSD) || canImport(Darwin)

import Testing
import PlatformExecutors

@Suite
struct PlatformExecutorTests {
  @Test()
  @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
  func test() async throws {
    await PlatformExecutorFactory.withTaskExecutor(name: "Test") { executor in
      #expect(await ExecutorFixture.test(executor: executor))
    }
    await PlatformExecutorFactory.withTaskPoolExecutor(name: "Test") { executor in
      #expect(await ExecutorFixture.test(executor: executor))
    }
    await PlatformExecutorFactory.withSerialExecutor(name: "Test") { executor in
      #expect(await ExecutorFixture.test(executor: executor))
    }
  }
}
#endif
