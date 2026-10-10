// swift-tools-version: 6.2
import PackageDescription

// Make sure that when the Swift Package Index builds our documentation,
// we enable BUILDING_DOCS.
import Foundation

var swiftSettings: [SwiftSetting] = []
if ProcessInfo.processInfo.environment["SPI_PROCESSING"] == "1"
  || ProcessInfo.processInfo.environment["BUILDING_DOCS"] == "1"
{
  swiftSettings.append(.define("BUILDING_DOCS"))
}

// The split continuation of swiftlang/swift#91981 is `anyAppleOS 9999` SPI in the toolchains that the I/O
// interfaces require, so availability checking is disabled for the library.
swiftSettings.append(
  .unsafeFlags(["-Xfrontend", "-disable-availability-checking"], .when(traits: ["ExperimentalIO"]))
)

let package = Package(
  name: "swift-platform-executors",
  products: [
    .library(
      name: "PlatformExecutors",
      targets: [
        "PlatformExecutors"
      ]
    )
  ],
  traits: [
    // The I/O interfaces require a toolchain that contains the split continuation of
    // https://github.com/swiftlang/swift/pull/91981, which wires through cancellation and priority
    // escalation of the operations. The toolchains can be downloaded from:
    // - Linux: https://download.swift.org/tmp/pull-request/91981/9/ubuntu2604/PR-ubuntu2604.tar.gz
    // - macOS: https://download.swift.org/tmp/pull-request/91981/2475/xcode/swift-PR-91981-2475-osx.tar.gz
    // On macOS, processes have to run against the Concurrency runtime of the toolchain, for example with
    // `DYLD_LIBRARY_PATH=<toolchain>/usr/lib/swift/macosx`.
    .trait(
      name: "ExperimentalIO",
      description: "Trait guarding experimental and highly unstable I/O interfaces"
    )
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
    .package(
      url: "https://github.com/apple/swift-collections.git",
      exact: "1.7.1",
      traits: [
        .defaults,
        .trait(name: "UnstableHashedContainers", condition: .when(traits: ["ExperimentalIO"])),
      ]
    ),
  ],
  targets: [
    .target(
      name: "PlatformExecutors",
      dependencies: [
        .target(name: "CPlatformExecutors"),
        .product(
          name: "BasicContainers",
          package: "swift-collections",
          condition: .when(traits: ["ExperimentalIO"])
        ),
        .product(
          name: "DequeModule",
          package: "swift-collections",
          condition: .when(traits: ["ExperimentalIO"])
        ),
      ],
      swiftSettings: swiftSettings
    ),
    .target(
      name: "CPlatformExecutors",
      cSettings: [
        .define("_GNU_SOURCE")
      ]
    ),

    // Tests
    .testTarget(
      name: "PlatformExecutorsTests",
      dependencies: [
        .target(name: "PlatformExecutors"),
        .target(name: "CPlatformExecutors"),
      ]
    ),

    // Examples
    .executableTarget(
      name: "PlatformExecutorsExample",
      dependencies: [
        .target(name: "PlatformExecutors")
      ],
      path: "Examples/PlatformExecutors"
    ),
    .executableTarget(
      name: "TCPPingPong",
      dependencies: [
        .target(name: "PlatformExecutors")
      ],
      path: "Examples/TCPPingPong"
    ),
    .executableTarget(
      name: "TCPEcho",
      dependencies: [
        .target(name: "PlatformExecutors")
      ],
      path: "Examples/TCPEcho"
    ),
  ]
)

for target in package.targets
where [.executable, .test, .regular].contains(
  target.type
) {
  var settings = target.swiftSettings ?? []

  // https://github.com/apple/swift-evolution/blob/main/proposals/0335-existential-any.md
  // Require `any` for existential types.
  //  settings.append(.enableUpcomingFeature("ExistentialAny"))

  // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0444-member-import-visibility.md
  //  settings.append(.enableUpcomingFeature("MemberImportVisibility"))

  // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md
  //  settings.append(.enableUpcomingFeature("InternalImportsByDefault"))

  // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md
  // Only enabled from Swift 6.4 on, since older compilers crash on parts of the code base with this feature enabled
  settings.append(.enableUpcomingFeature("NonisolatedNonsendingByDefault"))

  // Lifetime dependencies of non-escapable types such as the halves of a split TCP connection.
  settings.append(.enableExperimentalFeature("Lifetimes"))

  // `Builtin.stackAlloc` for temporary allocations that outlive the suspension points of an `async` function.
  settings.append(.enableExperimentalFeature("BuiltinModule"))

  //  // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0480-swiftpm-warning-control.md
  //  settings.append(.treatAllWarnings(as: .error))

  target.swiftSettings = settings
}
