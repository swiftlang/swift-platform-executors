# Swift Platform Executors

> [!WARNING]
> This package is currently still under active development.

This package provides platform-native executors for Swift Concurrency.

🚀 Swift package for Swift Concurrency executors
📦 Compatible with Swift Package Manager
📱 Supports Linux, Windows, iOS, macOS, watchOS, tvOS, visionOS, and WebAssembly (wasi-threads)
🔧 Built with Swift 6.2+, Xcode 26+

🔗 Jump to:
- 📖 [Overview](#overview)
- ⚙️ [Use Cases](#use-cases)
- 📋 [Glossary](#glossary)
- 🏁 [Getting Started](#getting-started)
- 📘 [Documentation](#documentation)
- 🧰 [Release Info](#release-info)
- 💡 [Contributing](#contributing)
- 🛠️ [Support](#support)
- 🔐 [Security](#security)
- 📄 [License](#license)

## 📖 Overview

This package provides high-performance platform-native executors for Swift
Concurrency that do not rely on Dispatch or Foundation to provide the job
scheduling system.


## ⚙️ Use Cases

The executors provided by this package are intended to be used as the default
executors on their respective platform. Furthermore, individual instances
of these executors can be created to provide custom actor or task executors.

## 🏁 Getting Started

### Prerequisites

- Swift version: 6.2+

### Installation / Integration

#### Adding as a Dependency

To use Swift Platform Executors in your Swift project, add it as a dependency in
 your `Package.swift` file:

```swift
.package(
  url: "https://github.com/swiftlang/swift-platform-executors",
  from: "0.0.1"
),
```

### Usage

Once [the relevant Swift Evolution proposal lands](https://github.com/swiftlang/swift-evolution/pull/2654/files),
it will be possible to replace the default main and global executors with
executors from this package.

To use the provided executors as the default executors in your application, add
the following type alias to the file including your appliation's main entry point.

```swift
import PlatformExecutors

typealias DefaultExecutorFactory = PlatformExecutorFactory
```

Be aware that if you take advantage of this option, the Dispatch main
queue will not be processed, so anything that relies explicitly on
`Dispatch.main` will not work.

The pthread executors (`PThreadMainExecutor`, `PThreadExecutor`,
`PThreadPoolExecutor`) are the platform executors on Linux, Apple platforms
and WebAssembly (`wasm32-unknown-wasip1-threads`).

#### Windows

##### `Win32EventLoopExecutor`

`Win32EventLoopExecutor` is a
[`SerialExecutor`](https://developer.apple.com/documentation/swift/serialexecutor)
and may be used as a [custom actor executor,
ala
SE-0392](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0392-custom-actor-executors.md):

```swift
import Win32NativeExecutors

actor Win32Actor {
  nonisolated let executor = Win32EventLoopExecutor()

  nonisolated var unownedExecutor: UnownedSerialExecutor {
    self.executor.asUnownedSerialExecutor()
  }

  func greet() {
    print("Hello from a Win32 event loop!")
    try? await Task.sleep(for: .seconds(3))
  }
}

func test() {
  let myActor = Win32Actor()
  let t = Task.detached {
    await myActor.greet()
    myActor.executor.stop()
  }
  myActor.executor.run()
}
```

This will also work for global actors, e.g.

```swift
import Win32NativeExecutors

@globalActor
actor MessageLoopActor {
  let executor = Win32EventLoopExecutor()

  nonisolated var unownedExecutor: UnownedSerialExecutor {
    self.executor.asUnownedSerialExecutor()
  }
}

@MessageLoopActor
func hello() {
  print("Hello from a Win32 event loop!")
  try? await Task.sleep(for: .seconds(3))
}

func test() {
  let t = Task.detached {
    await hello()
    myActor.executor.stop()
  }
  myActor.executor.run()
}
```

Note that you will need to call the `run()` method on the
`Win32EventLoopExecutor` from some thread to actually service the
message loop.  This will return on receipt of `WM_QUIT`, or if
something calls the `stop()` method (the latter is thread-safe and can
be done asynchronously; the message loop will stop when it is next
safe to do so).

###### `Win32ThreadPoolExecutor`

The `Win32ThreadPoolExecutor` is a
[`TaskExecutor`](https://developer.apple.com/documentation/swift/taskexecutor) 
built on [the Win32 Thread Pool
API](https://learn.microsoft.com/en-us/windows/win32/procthread/thread-pool-api)
and can be used with the
[`withTaskExecutorPreference(_:operation:)`](https://developer.apple.com/documentation/swift/withtaskexecutorpreference(_:isolation:operation:)),
[`Task(executorPreference:)`](https://developer.apple.com/documentation/swift/task/init(executorpreference:priority:operation:)-7zpzv)
or [`group.addTask(executorPreference:)`](https://developer.apple.com/documentation/swift/taskgroup/addtask(executorpreference:priority:operation:))
families of APIs:

```swift
import Win32NativeExecutors

let threadPool = Win32ThreadPoolExecutor()

func test() {
  Task {
     await withTaskExecutorPreference(threadPool) {
       print("I am running in the default Win32 thread pool")
     }
  }
}
```

If you have a custom Win32 thread pool that you wish to use instead,
you can use the `Win32ThreadPoolExecutor(pool: PTP_POOL?)` API to
construct an executor that will target that thread pool specifically.
Passing `nil` to that API will use the default pool.

## 📘 Documentation

- [API Documentation](https://swiftpackageindex.com/swiftlang/swift-platform-executors/documentation) - Complete API reference and guides

## 🧰 Release Info

This repository is released as a package.
- Release Cadence: Whenever new significant changes have landed on `main`.

## 💡 Contributing

We welcome contributions to Swift Platform Executors! 

To get started, please read the [Contributing Guide](https://www.swift.org/contributing/).

## 🛠️ Support

If you have any questions or need help, feel free to reach out by [opening an issue](https://github.com/swiftlang/swift-platform-executors/issues) or
contacting the maintainers.

- [GitHub Issues](https://github.com/swiftlang/swift-platform-executors/issues) - Bug reports and feature requests
- [CODEOWNERS](.github/CODEOWNERS)

This repo is part of the Platform Steering Group.

## 🔐 Security

If you discover a security vulnerability, please follow our
[security policy](https://github.com/swiftlang/swift-platform-executors?tab=security-ov-file)
 for responsible disclosure.

## License

This project is licensed under the terms of the [LICENSE](LICENSE.txt)
