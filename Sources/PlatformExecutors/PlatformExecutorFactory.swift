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

#if os(Windows)
/// Provides a reasonable default executor factory for your platform.
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct PlatformExecutorFactory: ExecutorFactory {
  public static let mainExecutor: any MainExecutor = Win32EventLoopExecutor(isMainExecutor: true)
  public static let defaultExecutor: any TaskExecutor = Win32ThreadPoolExecutor()

  /// Creates a new platform-native task executor.
  ///
  /// - Parameters:
  ///   - name: The base name for the executor.
  ///   - poolSize: The suggested number internal executors in the pool. Must be greater than 0.
  ///   Defaults to `nil` which uses a reasonable platform default.
  ///   - body: A closure that gets access to the task executor for the duration of the closure.
  public nonisolated(nonsending) static func withTaskExecutor<Return, Failure: Error>(
    name: String,
    poolSize: Int? = nil,
    body: (PlatformTaskExecutor) async throws(Failure) -> Return
  ) async throws(Failure) -> Return {
    fatalError()
  }

  /// Creates a new platform-native serial executor .
  ///
  /// - Parameters:
  ///   - name: The base name for the executor.
  ///   - body: A closure that gets access to the serial executor for the duration of the closure.
  public nonisolated(nonsending) static func withSerialExecutor<Return, Failure: Error>(
    name: String,
    body: (PlatformSerialExecutor) async throws(Failure) -> Return
  ) async throws(Failure) -> Return {
    fatalError()
  }
}
#elseif canImport(Darwin)
/// Provides a reasonable default executor factory for your platform.
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct PlatformExecutorFactory: ExecutorFactory {
  public static let mainExecutor: any MainExecutor = DispatchMainExecutor()
  public static let defaultExecutor: any TaskExecutor = DispatchGlobalTaskExecutor()

  /// Creates a new platform-native task executor.
  ///
  /// - Parameters:
  ///   - name: The base name for the executor.
  ///   - poolSize: The suggested number internal executors in the pool. Must be greater than 0.
  ///   Defaults to `nil` which uses a reasonable platform default.
  ///   - body: A closure that gets access to the task executor for the duration of the closure.
  public nonisolated(nonsending) static func withTaskExecutor<Return, Failure: Error>(
    name: String,
    poolSize: Int? = nil,
    body: (PlatformTaskExecutor) async throws(Failure) -> Return
  ) async throws(Failure) -> Return {
    let platformExecutor = PlatformTaskExecutor()
    platformExecutor.executor = DispatchTaskExecutor(
      name: name,
      taskExecutor: platformExecutor.asUnownedTaskExecutor()
    )
    return try await body(platformExecutor)
  }

  /// Creates a new platform-native serial executor .
  ///
  /// - Parameters:
  ///   - name: The base name for the executor.
  ///   - body: A closure that gets access to the serial executor for the duration of the closure.
  public nonisolated(nonsending) static func withSerialExecutor<Return, Failure: Error>(
    name: String,
    body: (PlatformSerialExecutor) async throws(Failure) -> Return
  ) async throws(Failure) -> Return {
    let platformExecutor = PlatformSerialExecutor()
    platformExecutor.executor = DispatchSerialExecutor(
      name: name,
      serialExecutor: platformExecutor.asUnownedSerialExecutor()
    )
    return try await body(platformExecutor)
  }
}

#elseif os(Linux) || os(FreeBSD)
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Provides a reasonable default executor factory for your platform.
///
/// By default the size of the ``defaultExecutor`` is determined by the systems available core count.
/// On Linux this takes into account C1 and C2 group restrictions. Additionally, the size can be customized
/// by setting the `SWIFT_PLATFORM_DEFAULT_EXECUTOR_POOL_SIZE` environment variable.
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct PlatformExecutorFactory: ExecutorFactory {
  public static let mainExecutor: any MainExecutor = PThreadMainExecutor()
  public static let defaultExecutor: any TaskExecutor = {
    let coreCountEnvironment = ProcessInfo.processInfo
      .environment["SWIFT_PLATFORM_DEFAULT_EXECUTOR_POOL_SIZE"]
    let coreCount = coreCountEnvironment.flatMap { Int($0) } ?? SystemCoreCount.coreCount
    return PThreadTaskExecutor(
      name: "global",
      poolSize: coreCount,
      taskExecutor: nil
    )
  }()

  /// Creates a new platform-native task executor.
  ///
  /// - Parameters:
  ///   - name: The base name for the executor.
  ///   - poolSize: The suggested number internal executors in the pool. Must be greater than 0.
  ///   Defaults to `nil` which uses a reasonable platform default.
  ///   - body: A closure that gets access to the task executor for the duration of the closure.
  public nonisolated(nonsending) static func withTaskExecutor<Return, Failure: Error>(
    name: String,
    poolSize: Int? = nil,
    body: (PlatformTaskExecutor) async throws(Failure) -> Return
  ) async throws(Failure) -> Return {
    do {
      do {
        let platformExecutor = PlatformTaskExecutor()
        return try await PThreadTaskExecutor._withExecutor(
          name: name,
          poolSize: poolSize,
          taskExecutor: platformExecutor.asUnownedTaskExecutor()
        ) { executor in
          platformExecutor.executor = executor
          return try await body(platformExecutor)
        }
      } catch {
        // This is the only possible error thrown but somehow the compiler trips up
        throw error as! Failure
      }
    }
  }

  /// Creates a new platform-native serial executor .
  ///
  /// - Parameters:
  ///   - name: The base name for the executor.
  ///   - body: A closure that gets access to the serial executor for the duration of the closure.
  public nonisolated(nonsending) static func withSerialExecutor<Return, Failure: Error>(
    name: String,
    body: (PlatformSerialExecutor) async throws(Failure) -> Return
  ) async throws(Failure) -> Return {
    do {
      let platformExecutor = PlatformSerialExecutor()
      return try await PThreadSerialExecutor._withExecutor(
        name: name,
        serialExecutor: platformExecutor.asUnownedSerialExecutor()
      ) { executor in
        platformExecutor.executor = executor
        return try await body(platformExecutor)
      }
    } catch {
      // This is the only possible error thrown but somehow the compiler trips up
      throw error as! Failure
    }
  }
}
#else
typealias PlatformExecutorFactory = _Concurrency.PlatformExecutorFactory
#endif
