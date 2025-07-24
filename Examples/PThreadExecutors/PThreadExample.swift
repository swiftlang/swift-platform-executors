import PlatformExecutors
import Dispatch

@available(macOS 26.0, *)
typealias DefaultExecutorFactory = PlatformExecutorFactory

@main
@available(macOS 26, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
struct Example {
  static func main() async throws {
//    print(Task.currentExecutor)
    let pThreadExecutor = PThreadExecutor(name: "Executor")
    let pThreadPoolExecutor = PThreadPoolExecutor(name: "Pool", poolSize: 10)
    let dispatchExecutor = DispatchTaskExecutor(queue: DispatchQueue(label: "Queue"))
//    let pThread = try await ContinuousClock().measure {
//      try await run(executor: pThreadExecutor)
//    }
//    print("pthread", pThread)
//    try await Task.sleep(for: .seconds(1))
//
//    let pThreadPool = try await ContinuousClock().measure {
//      try await run(executor: pThreadPoolExecutor)
//    }
//    print("pThreadPool", pThreadPool)
//    try await Task.sleep(for: .seconds(1))
//
//    let dispatch = try await ContinuousClock().measure {
//      try await run(executor: dispatchExecutor)
//    }
//    print("dispatch", dispatch)
//    try await Task.sleep(for: .seconds(1))
//
//    let global = try await ContinuousClock().measure {
//      try await runGlobal()
//    }
//    print("global", global)
//
//    let pThreadPoolGroup = try await ContinuousClock().measure {
//      try await runGroup(executor: pThreadPoolExecutor)
//    }
//    print("pThreadPoolGroup", pThreadPoolGroup)
//    try await Task.sleep(for: .seconds(1))

    let globalGroup = try await ContinuousClock().measure {
      try await runGroupGlobal()
    }
    print("globalGroup", globalGroup)
  }

  @concurrent static func run(executor: TaskExecutor) async throws {
    await withTaskExecutorPreference(executor) {
      for _ in 0..<10_000_000 {
        await withUnsafeContinuation { cont in
          cont.resume()
        }
      }
    }
  }

  @concurrent static func runGroup(executor: TaskExecutor) async throws {
    await withTaskExecutorPreference(executor) {
      await withTaskGroup { group in
        for _ in 0..<10 {
          group.addTask(executorPreference: executor) {
            for _ in 0..<10_000_000 {
              await withUnsafeContinuation { cont in
                cont.resume()
              }
            }
          }
        }
      }
    }
  }

  @concurrent static func runGroupGlobal() async throws {
    await withTaskGroup { group in
      for _ in 0..<3 {
        group.addTask() {
          for _ in 0..<3 {
            await withUnsafeContinuation { cont in
              cont.resume()
            }
          }
        }
      }
    }
  }

  @concurrent static func runGlobal() async throws {
//    print(Task.currentExecutor)
    for _ in 0..<10_000_000 {
      await withUnsafeContinuation { cont in
        cont.resume()
      }
    }
  }
}

@available(macOS 15.4, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
final class DispatchTaskExecutor: TaskExecutor, SerialExecutor {
  private let queue: DispatchQueue

  init(queue: DispatchQueue) {
    self.queue = queue
  }

  func enqueue(_ job: UnownedJob) {
    queue.async {
      job.runSynchronously(on: self.asUnownedTaskExecutor())
    }
  }
}
