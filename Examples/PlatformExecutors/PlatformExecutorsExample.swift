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

import PlatformExecutors
import Dispatch

@available(macOS 26, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
typealias DefaultExecutorFactory = PlatformExecutorFactory

@main
@available(macOS 26, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
struct Example {
  static func main() async throws {
    await self.run(executor: nil)
    await self.runGroup(executor: nil)

    await PlatformExecutorFactory.withTaskExecutor(name: "PlatformTask") { executor in
      await self.run(executor: executor)
    }
    await PlatformExecutorFactory.withTaskPoolExecutor(name: "PlatformPool") { executor in
      await self.run(executor: executor)
    }
    await PlatformExecutorFactory.withSerialExecutor(name: "PlatformSerial") { executor in
      await Run(executor: executor).run()
    }

    #if os(Linux) || os(Android) || os(FreeBSD) || canImport(Darwin)
    await PThreadExecutor.withExecutor(name: "PThreadTaskExecutor") { executor in
      await self.run(executor: executor)
    }
    await PThreadPoolExecutor.withExecutor(name: "PThreadPool") { executor in
      await self.run(executor: executor)
    }
    await PThreadSerialExecutor.withExecutor(name: "PThreadSerial") { executor in
      await Run(executor: executor).run()
    }
    #endif
  }

  @concurrent
  static func run(
    executor: TaskExecutor?,
    iterations: Int = 10_000_000
  ) async {
    let duration = await ContinuousClock().measure {
      await withTaskExecutorPreference(executor) {
        for _ in 0..<iterations {
          await withUnsafeContinuation { cont in
            cont.resume()
          }
        }
      }
    }

    print(
      "Executor \(executor.debugDescription) took \(duration) seconds for \(iterations) iterations"
    )
  }

  @concurrent
  static func runGroup(
    executor: TaskExecutor?,
    childTasks: Int = 10,
    iterations: Int = 10_000_000
  ) async {
    let duration = await ContinuousClock().measure {
      await withTaskExecutorPreference(executor) {
        await withTaskGroup { group in
          for _ in 0..<childTasks {
            group.addTask {
              for _ in 0..<iterations {
                await withUnsafeContinuation { cont in
                  cont.resume()
                }
              }
            }
          }
        }
      }
    }

    print(
      "Executor \(executor.debugDescription) took \(duration) seconds for \(iterations) iterations with \(childTasks) child tasks"
    )
  }
}

@available(macOS 26, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
actor Run {
  nonisolated var unownedExecutor: UnownedSerialExecutor {
    self.executor.asUnownedSerialExecutor()
  }
  private let executor: any SerialExecutor

  init(executor: any SerialExecutor) {
    self.executor = executor
  }

  func run(
    iterations: Int = 10_000_000
  ) async {
    let duration = await ContinuousClock().measure {
      for _ in 0..<iterations {
        await withUnsafeContinuation { cont in
          cont.resume()
        }
      }
    }

    print(
      "Actor with executor \(String(describing: self.executor)) took \(duration) seconds for \(iterations) iterations"
    )
  }
}
