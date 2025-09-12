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

#if canImport(Darwin)
import CPlatformExecutors
import Dispatch

// Thread-safe initialization of the dispatch function pointer
private let dispatchAsyncSwiftJobFunc: (@convention(c) (DispatchQueue, UnsafeMutableRawPointer, UInt32) -> Void)? = {
  guard let symbol = dlsym(CPlatformExecutors_RTLD_NEXT, "dispatch_async_swift_job") else {
    return nil
  }
  return unsafeBitCast(symbol, to: (@convention(c) (DispatchQueue, UnsafeMutableRawPointer, UInt32) -> Void).self)
}()

@available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
private let _enqueueJobOnTaskExecutor: @Sendable (DispatchQueue, UnownedJob, UnownedTaskExecutor) -> Void = {
  guard let dispatchAsyncSwiftJobFunc else {
    // We can't find the `dispatch_async_swift_job` method so let's fallback
    return { queue, job, taskExecutor in
      queue.async {
        job.runSynchronously(on: taskExecutor)
      }
    }
  }
  return { queue, job, _ in
    // Convert UnownedJob to a raw pointer for C interface
    // Dispatch is storing this pointer after the call to enqueue as well so we
    // cannot use a scoped with-style method here
    let jobPointer = unsafeBitCast(job, to: UnsafeMutableRawPointer.self)
    dispatchAsyncSwiftJobFunc(
      queue,
      jobPointer,
      qosClassForPriority(job.priority).rawValue.rawValue
    )
  }
}()

@available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
private let _enqueueJobOnSerialExecutor: @Sendable (DispatchQueue, UnownedJob, UnownedSerialExecutor) -> Void = {
  guard let dispatchAsyncSwiftJobFunc else {
    // We can't find the `dispatch_async_swift_job` method so let's fallback
    return { queue, job, serialExecutor in
      queue.async {
        job.runSynchronously(on: serialExecutor)
      }
    }
  }
  return { queue, job, _ in
    // Convert UnownedJob to a raw pointer for C interface
    // Dispatch is storing this pointer after the call to enqueue as well so we
    // cannot use a scoped with-style method here
    let jobPointer = unsafeBitCast(job, to: UnsafeMutableRawPointer.self)
    dispatchAsyncSwiftJobFunc(
      queue,
      jobPointer,
      qosClassForPriority(job.priority).rawValue.rawValue
    )
  }
}()

// Cached global dispatch queues for performance using tuple for O(1) access
private let globalQueues:
  (
    userInteractive: DispatchQueue,
    userInitiated: DispatchQueue,
    default: DispatchQueue,
    utility: DispatchQueue,
    background: DispatchQueue
  ) = (
    userInteractive: DispatchQueue.global(qos: .userInteractive),
    userInitiated: DispatchQueue.global(qos: .userInitiated),
    default: DispatchQueue.global(qos: .default),
    utility: DispatchQueue.global(qos: .utility),
    background: DispatchQueue.global(qos: .background)
  )

// Convert job priority to dispatch QoS class
@available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
private func qosClassForPriority(_ priority: JobPriority) -> DispatchQoS.QoSClass {
  DispatchQoS.QoSClass(rawValue: .init(UInt32(priority.rawValue))) ?? .default
}

// Get cached global queue for priority with O(1) tuple access
@available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
private func getGlobalQueue(for priority: JobPriority) -> DispatchQueue {
  switch qosClassForPriority(priority) {
  case .userInteractive:
    return globalQueues.userInteractive
  case .userInitiated:
    return globalQueues.userInitiated
  case .default:
    return globalQueues.default
  case .utility:
    return globalQueues.utility
  case .background:
    return globalQueues.background
  default:
    return globalQueues.default
  }
}

// MARK: - Public Runtime Methods

@available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
internal func _dispatchMain() -> Never {
  CPlatformExecutors_dispatchMain()
}

@available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
internal func _dispatchEnqueueMain(
  _ job: UnownedJob,
  serialExecutor: UnownedSerialExecutor
) {
  _enqueueJobOnSerialExecutor(DispatchQueue.main, job, serialExecutor)
}

@available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
internal func _dispatchAssertMainQueue() {
  dispatchPrecondition(condition: .onQueue(.main))
}

@available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999, *)
internal func _dispatchEnqueueGlobal(_ job: UnownedJob, taskExecutor: UnownedTaskExecutor) {
  _enqueueJobOnTaskExecutor(getGlobalQueue(for: job.priority), job, taskExecutor)
}
#endif
