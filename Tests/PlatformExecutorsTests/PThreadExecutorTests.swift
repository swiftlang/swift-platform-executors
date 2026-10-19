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

import CPlatformExecutors
import Testing
@_spi(ExperimentalScheduling) @_spi(ConcurrencyExecutors) @_spi(ExperimentalCustomExecutors) import _Concurrency
@_spi(ExperimentalScheduling) @_spi(ConcurrencyExecutors) @_spi(ExperimentalCustomExecutors) import PlatformExecutors

@Suite
struct PThreadExecutorTests {
  @Test(arguments: PThreadIOBackend.tested)
  @available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
  func singleExecutor(ioBackend: PThreadIOBackend) async {
    await PThreadTaskExecutor
      .withExecutor(name: "Test", poolSize: 1, ioBackend: ioBackend) { executor in
        await withTaskExecutorPreference(executor) {
          for _ in 0...100 {
            await Task.yield()
          }
        }
      }
  }

  @Test(arguments: PThreadIOBackend.tested)
  @available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
  func poolExecutor(ioBackend: PThreadIOBackend) async {
    await PThreadTaskExecutor.withExecutor(
      name: "Test",
      poolSize: 5,
      ioBackend: ioBackend
    ) { executor in
      await withTaskExecutorPreference(executor) {
        for _ in 0...100 {
          await Task.yield()
        }
      }
    }
  }

  @Test(arguments: PThreadIOBackend.tested)
  @available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
  func taskExecutorStackSize(ioBackend: PThreadIOBackend) async {
    let stackSize = 64 << 20
    await PThreadTaskExecutor.withExecutor(
      name: "BigStack",
      poolSize: 2,
      stackSize: stackSize,
      ioBackend: ioBackend
    ) { executor in
      await withTaskGroup { group in
        for _ in 0..<10 {
          group.addTask(executorPreference: executor) {
            #expect(CPlatformExecutors_pthread_current_stack_size() >= stackSize)
          }
        }
      }
    }
  }

  @Test(arguments: PThreadIOBackend.tested)
  @available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
  func serialExecutorStackSize(ioBackend: PThreadIOBackend) async {
    let stackSize = 64 << 20
    await PThreadSerialExecutor.withExecutor(
      name: "BigStack",
      stackSize: stackSize,
      ioBackend: ioBackend
    ) { executor in
      let actor = StackSizeActor(executor: executor)
      #expect(await actor.currentStackSize() >= stackSize)
    }
  }

  @Test(arguments: PThreadIOBackend.tested)
  @available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
  func stackSizeIsRoundedUp(ioBackend: PThreadIOBackend) async {
    // Not a page multiple and below the 128 KiB floor, which is enforced
    // because PTHREAD_STACK_MIN is too small to run Swift code on x86_64 glibc
    let stackSize = 1001
    await PThreadTaskExecutor.withExecutor(
      name: "TinyStack",
      poolSize: 1,
      stackSize: stackSize,
      ioBackend: ioBackend
    ) { executor in
      await Task(executorPreference: executor) {
        #expect(CPlatformExecutors_pthread_current_stack_size() >= 128 * 1024)
      }.value
    }
  }

  @Test(arguments: PThreadIOBackend.tested)
  @available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
  func test(ioBackend: PThreadIOBackend) async throws {
    await PThreadExecutor.withExecutor(name: "Test", ioBackend: ioBackend) { executor in
      #expect(await ExecutorFixture.test(executor: executor))
    }
    await PThreadTaskExecutor.withExecutor(name: "Test", ioBackend: ioBackend) { executor in
      #expect(await ExecutorFixture.test(executor: executor))
    }
    await PThreadSerialExecutor.withExecutor(name: "Test", ioBackend: ioBackend) { executor in
      #expect(await ExecutorFixture.test(executor: executor))
    }
  }

  @Test(.timeLimit(.minutes(1)), arguments: PThreadIOBackend.tested)
  @available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
  func shortSleepsWhoseDeadlinePassesWhileTheExecutorPreparesToWait(ioBackend: PThreadIOBackend) async {
    await PThreadTaskExecutor.withExecutor(name: "Test", poolSize: 1, ioBackend: ioBackend) { executor in
      await withTaskExecutorPreference(executor) {
        await withTaskGroup(of: Void.self) { group in
          for _ in 0..<16 {
            group.addTask {
              for _ in 0..<500 {
                try? await Task.sleep(for: .microseconds(100))
              }
            }
          }
        }
      }

      await withTaskExecutorPreference(executor) {
        for _ in 0..<5_000 {
          try? await Task.sleep(for: .microseconds(20))
        }
      }
    }
  }

  /// A sleep with an earlier deadline must wake an executor that already waits for a later one.
  @Test(.timeLimit(.minutes(1)), arguments: PThreadIOBackend.tested)
  @available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
  func anEarlierSleepFiresWhileALaterOneIsPending(ioBackend: PThreadIOBackend) async {
    await Self.anEarlierSleepFiresWhileALaterOneIsPending(clock: ContinuousClock(), ioBackend: ioBackend)
    await Self.anEarlierSleepFiresWhileALaterOneIsPending(clock: SuspendingClock(), ioBackend: ioBackend)
  }

  @available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
  private static func anEarlierSleepFiresWhileALaterOneIsPending<C: Clock>(
    clock: C,
    ioBackend: PThreadIOBackend
  ) async where C.Duration == Duration {
    await PThreadTaskExecutor.withExecutor(name: "Test", poolSize: 1, ioBackend: ioBackend) { executor in
      let later = Task(executorPreference: executor) {
        try? await Task.sleep(for: .seconds(30), clock: clock)
      }
      // Give the executor time to wait for the later deadline.
      try? await Task.sleep(for: .milliseconds(200))
      let start = ContinuousClock.now
      await Task(executorPreference: executor) {
        try? await Task.sleep(for: .milliseconds(50), clock: clock)
      }.value
      #expect(start.duration(to: .now) < .seconds(10))
      later.cancel()
      await later.value
    }
  }

  /// Once a timer fired, the next sleeps must arm it again.
  @Test(.timeLimit(.minutes(1)), arguments: PThreadIOBackend.tested)
  @available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
  func sleepsOneAfterAnotherEachFire(ioBackend: PThreadIOBackend) async {
    await PThreadTaskExecutor.withExecutor(name: "Test", poolSize: 1, ioBackend: ioBackend) { executor in
      await withTaskExecutorPreference(executor) {
        for _ in 0..<5 {
          try? await Task.sleep(for: .milliseconds(20), clock: ContinuousClock())
          try? await Task.sleep(for: .milliseconds(20), clock: SuspendingClock())
        }
      }
    }
  }

  @Test
  @available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
  func mainExecutor() async throws {
    let mainExecutor = PThreadMainExecutor()
    #expect(await ExecutorFixture.test(executor: mainExecutor))
    // We are manually shutting it down since normally it is expeceted to live
    // for the entire duration of a process
    //    mainExecutor.pThreadExecutor.shutdown()
  }
}

@available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
private actor StackSizeActor {
  let executor: PThreadSerialExecutor

  init(executor: PThreadSerialExecutor) {
    self.executor = executor
  }

  nonisolated var unownedExecutor: UnownedSerialExecutor {
    self.executor.asUnownedSerialExecutor()
  }

  func currentStackSize() -> Int {
    CPlatformExecutors_pthread_current_stack_size()
  }
}
#endif
