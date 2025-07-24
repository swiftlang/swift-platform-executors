import PlatformExecutors
import Dispatch

@available(macOS 26.0, *)
typealias ExecutorFactory = PlatformExecutorFactory

@main
@available(macOS 15.4, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
struct Example {
  static func main() async throws {
    let pThreadExecutor = PThreadExecutor(name: "Executor")
    let dispatchExecutor = DispatchTaskExecutor(queue: DispatchQueue(label: "Queue"))
    let pThread = try await ContinuousClock().measure {
      try await run(executor: pThreadExecutor)
    }
    print(pThread)
    try await Task.sleep(for: .seconds(1))
    let dispatch = try await ContinuousClock().measure {
      try await run(executor: dispatchExecutor)
    }
    print(dispatch)
  }

  nonisolated static func run(executor: TaskExecutor) async throws {
    await withTaskExecutorPreference(executor) {
      for _ in 0..<30_000_000 {
        await withUnsafeContinuation { cont in
          cont.resume()
        }
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
