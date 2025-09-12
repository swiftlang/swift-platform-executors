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

#if os(Linux) || os(FreeBSD) || canImport(Darwin) || os(Windows)

import Testing
import PlatformExecutors

@Suite
struct PlatformExecutorTests {
  @Test()
  @available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
  func test() async throws {
    await PlatformExecutorFactory.withTaskExecutor(name: "Test") { executor in
      #expect(await ExecutorFixture.test(executor: executor))
    }
    await PlatformExecutorFactory.withSerialExecutor(name: "Test") { executor in
      #expect(await ExecutorFixture.test(executor: executor))
    }
  }
}

#endif
