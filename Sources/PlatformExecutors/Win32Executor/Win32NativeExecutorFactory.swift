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

/// An ``ExecutorFactory`` that vends ``Win32EventLoopExecutor`` and
/// ``Win32ThreadPoolExecutor``.
///
/// This factory will result in your program running a Windows event loop on
/// its main thread, and relying on a Win32 Thread Pool to schedule tasks.
///
/// Note that the default thread pool size is of the order of 500
/// threads; if your program is CPU-bound, you may wish to use a
/// different `defaultExecutor`, or you might want to schedule
/// CPU-bound work onto a separate thread pool executor configured
/// with a more reasonable thread count for the system on which you
/// are running.
///
public struct Win32NativeExecutorFactory: ExecutorFactory {
  public static var mainExecutor: any MainExecutor { Win32EventLoopExecutor(isMainExecutor: true) }
  public static var defaultExecutor: any TaskExecutor { Win32ThreadPoolExecutor() }
}
