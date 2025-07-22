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
public struct PlatformExecutorFactory: ExecutorFactory {
  public static var mainExecutor: any MainExecutor {
    fatalError("TODO")
    // PThreadMainExecutor()
  }
  public static var defaultExecutor: any TaskExecutor {
    // FIXME: The default pool size should be sensible for the hardware
    // we're running on.
    PThreadPoolExecutor(name: "Default Global Executor", poolSize: 16)
  }
}
#else
#error("Unsupported platform")
#endif
