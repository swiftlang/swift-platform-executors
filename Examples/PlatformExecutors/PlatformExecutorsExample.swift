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

#if canImport(Darwin)
import Dispatch
#endif

@available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
typealias DefaultExecutorFactory = PlatformExecutorFactory

@main
@available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
struct Example {
  static func main() async throws {
    print("Starting executor example")

    // Default executor
    await self.run(executor: nil)
    await self.runGroup(executor: nil)

    // Platform executors
    await PlatformExecutorFactory.withTaskExecutor(name: "PlatformTask") { executor in
      await self.run(executor: executor)
    }
    await PlatformExecutorFactory.withSerialExecutor(name: "PlatformSerial") { executor in
      await Run(executor: executor).run()
    }

    // DispatchQueue based executors
    #if canImport(Darwin)  // Gated by Darwin because the conformances only exist on Darwin
    await self.run(executor: DispatchQueue(label: "Queue"))
    // Disabled the below for now since it takes the slow path in the current
    // Dispatch implementation
    //    await self.runGroup(executor: DispatchQueue.global())
    await Run(
      executor: DispatchSerialQueue(label: "Serial Queue")
        as! (
          any SerialExecutor
        )  // The conformance to SerialExecutor is availaiblity gated but the
      // compiler isn't capable of finding it in a #if
    ).run()
    await self.run(executor: DispatchGlobalTaskExecutor())
    await self.runGroup(executor: DispatchGlobalTaskExecutor())
    #endif

    // PThread based executors
    #if os(Linux) || os(Android) || os(FreeBSD) || canImport(Darwin)
    await PThreadExecutor.withExecutor(name: "PThreadTaskExecutor") { executor in
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

@available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
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
