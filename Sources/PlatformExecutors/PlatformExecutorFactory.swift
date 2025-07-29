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
public struct PlatformExecutorFactory: ExecutorFactory {
  public static let mainExecutor: any MainExecutor = Win32EventLoopExecutor(isMainExecutor: true)
  public static let defaultExecutor: any TaskExecutor = Win32ThreadPoolExecutor()
}
#elseif os(Linux) || os(FreeBSD) || canImport(Darwin)
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
    return PThreadPoolExecutor(
      name: "global",
      poolSize: coreCount
    )
  }()
}
#else
#error("Unsupported platform")
#endif
