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
  public static var mainExecutor: any MainExecutor { Win32EventLoopExecutor(isMainExecutor: true) }
  public static var defaultExecutor: any TaskExecutor { Win32ThreadPoolExecutor() }
}
#elseif os(Linux) || os(FreeBSD) || canImport(Darwin)
/// Provides a reasonable default executor factory for your platform.
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct PlatformExecutorFactory: ExecutorFactory {
  public static var mainExecutor: any MainExecutor {
    print("Creating main")
     return PThreadMainExecutor()
  }
  public static var defaultExecutor: any TaskExecutor {
    print("Creating global")
    return PThreadPoolExecutor(name: "global", poolSize: 8, isGlobal: false)
  }
}
#else
#error("Unsupported platform")
#endif
