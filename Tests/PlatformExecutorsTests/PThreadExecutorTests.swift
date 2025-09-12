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
  @available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
  func singleExecutor() async {
    await PThreadTaskExecutor
      .withExecutor(name: "Test", poolSize: 1) { executor in
        await withTaskExecutorPreference(executor) {
          for _ in 0...100 {
            await Task.yield()
          }
        }
      }
  }

  @Test
  @available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
  func poolExecutor() async {
    await PThreadTaskExecutor.withExecutor(
      name: "Test",
      poolSize: 5
    ) { executor in
      await withTaskExecutorPreference(executor) {
        for _ in 0...100 {
          await Task.yield()
        }
      }
    }
  }

  @Test
  @available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
  func test() async throws {
    await PThreadExecutor.withExecutor(name: "Test") { executor in
      #expect(await ExecutorFixture.test(executor: executor))
    }
    await PThreadTaskExecutor.withExecutor(name: "Test") { executor in
      #expect(await ExecutorFixture.test(executor: executor))
    }
    await PThreadSerialExecutor.withExecutor(name: "Test") { executor in
      #expect(await ExecutorFixture.test(executor: executor))
    }

    let mainExecutor = PThreadMainExecutor()
    #expect(await ExecutorFixture.test(executor: mainExecutor))
    // We are manually shutting it down since normally it is expeceted to live
    // for the entire duration of a process
    //    mainExecutor.pThreadExecutor.shutdown()
  }
}
#endif
