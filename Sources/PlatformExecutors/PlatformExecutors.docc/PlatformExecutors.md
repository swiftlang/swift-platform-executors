# Swift Platform Executors

This package provides platform-native executors for Swift Concurrency that
do not rely on Dispatch or Foundation to provide the job scheduling system.

## Getting Started

Below is a description of the steps you need to take to use this
package.

#### Add the dependency

You will need to add the dependency to your `Package.swift`, as show
below:

```swift
.package(
  url: "https://github.com/swiftlang/swift-platform-executors",
  from: "0.0.1"
),
```

You will also need to add it to your application or library target,
e.g:

```swift
.target(name: "MyApplication", dependencies: ["SwiftPlatformExecutors"]),
```

#### Using the executors portably

If you want to make use of the executors from this package, but in a
way that will work no matter what platform you are on (assuming the
package currently supports your platform), you can use the
``PlatformExecutorFactory`` type.

Once [the relevant Swift Evolution proposal
lands](https://github.com/swiftlang/swift-evolution/pull/2654/files),
you will be able to add

```swift
import PlatformExecutors

typealias DefaultExecutorFactory
  = PlatformExecutors.PlatformExecutorFactory
```

either at top level, or in your `@main`, and you'll automatically pick
up the relevant executors.

Be aware that currently, if you take advantage of this option, the
Dispatch main queue will not be processed, so anything that relies
explicitly on `Dispatch.main` will not work.

Alternatively, you can reach into the ``PlatformExecutorFactory`` type
and get it to construct executors as required.

#### Platform specific executors

Alternatively, you can use the following platform specific executors:

* ``Win32EventLoopExecutor``
* ``Win32ThreadPoolExecutor``
* ``PThreadMainExecutor``
* ``PThreadExecutor``
* ``PThreadPoolExecutor``
