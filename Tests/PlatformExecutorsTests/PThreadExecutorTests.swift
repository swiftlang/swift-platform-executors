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
struct PThreadExecutorTests {
  @Test
  @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
  func singleExecutor() async {
    let executor = PThreadExecutor(name: "Test")
    await withTaskExecutorPreference(executor) {
      for _ in 0...100 {
        await Task.yield()
      }
    }
  }

  @Test
  @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
  func poolExecutor() async {
    let executor = PThreadPoolExecutor(name: "Test", poolSize: 5)
    await withTaskExecutorPreference(executor) {
      for _ in 0...100 {
        await Task.yield()
      }
    }
  }

  @Test(
    arguments: [
      PThreadExecutor(name: "Test") as any Executor,
      PThreadPoolExecutor(name: "Test", poolSize: 1),
      PThreadPoolExecutor(name: "Test", poolSize: 5),
      PThreadMainExecutor(),
    ]
  )
  @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
  func foo(executor: any Executor) async throws {
    #expect(await ExecutorFixture.test(executor: executor))
  }
}
#endif
