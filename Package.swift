// swift-tools-version: 6.4
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
    ),
    // Performs the I/O of the PThread based executors with `io_uring` on Linux.
    .trait(
      name: "ExperimentalIOUring",
      description: "Trait performing the I/O with io_uring on Linux",
      enabledTraits: ["ExperimentalIO"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
    // Uses a custom branch until the io_uring socket APIs land
    .package(url: "https://github.com/apple/swift-system.git", branch: "fb-io-uring-sockets"),
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
        .product(name: "BasicContainers", package: "swift-collections"),
        .product(
          name: "DequeModule",
          package: "swift-collections",
          condition: .when(traits: ["ExperimentalIO"])
        ),
        .product(
          name: "SystemPackage",
          package: "swift-system",
          condition: .when(platforms: [.linux], traits: ["ExperimentalIOUring"])
        ),
        .product(
          name: "SystemSockets",
          package: "swift-system",
          condition: .when(platforms: [.linux], traits: ["ExperimentalIOUring"])
        ),
      ],
      exclude: ["CMakeLists.txt"],
      swiftSettings: swiftSettings
    ),
    .target(
      name: "CPlatformExecutors",
      exclude: ["CMakeLists.txt"],
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
        .product(
          name: "BasicContainers",
          package: "swift-collections",
          condition: .when(traits: ["ExperimentalIO"])
        ),
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
    .executableTarget(
      name: "FileExample",
      dependencies: [
        .target(name: "PlatformExecutors"),
        .product(
          name: "BasicContainers",
          package: "swift-collections",
          condition: .when(traits: ["ExperimentalIO"])
        ),
      ],
      path: "Examples/File"
    ),
  ]
)

// The availability macros of the Swift standard library, the same as swift-collections defines them.
let availabilityMacros: KeyValuePairs<String, String> = [
  "SwiftStdlib 5.0": "macOS 10.14.4, iOS 12.2, watchOS 5.2, tvOS 12.2",
  "SwiftStdlib 5.1": "macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0",
  "SwiftStdlib 5.6": "macOS 12.3, iOS 15.4, watchOS 8.5, tvOS 15.4",
  "SwiftStdlib 5.7": "macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0",
  "SwiftStdlib 5.8": "macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4",
  "SwiftStdlib 5.9": "macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0",
  "SwiftStdlib 5.10": "macOS 14.4, iOS 17.4, watchOS 10.4, tvOS 17.4, visionOS 1.1",
  "SwiftStdlib 6.0": "macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0",
  "SwiftStdlib 6.1": "macOS 15.4, iOS 18.4, watchOS 11.4, tvOS 18.4, visionOS 2.4",
  "SwiftStdlib 6.2": "macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0",
  "SwiftStdlib 6.3": "macOS 26.4, iOS 26.4, watchOS 26.4, tvOS 26.4, visionOS 26.4",
  "SwiftStdlib 6.4": "macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0",
  "SwiftStdlib 6.5": "macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999",
]

for target in package.targets
where [.executable, .test, .regular].contains(
  target.type
) {
  var settings = target.swiftSettings ?? []

  // https://github.com/apple/swift-evolution/blob/main/proposals/0335-existential-any.md
  // Require `any` for existential types.
  settings.append(.enableUpcomingFeature("ExistentialAny"))

  // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0444-member-import-visibility.md
  settings.append(.enableUpcomingFeature("MemberImportVisibility"))

  // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md
  settings.append(.enableUpcomingFeature("InternalImportsByDefault"))

  // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md
  settings.append(.enableUpcomingFeature("NonisolatedNonsendingByDefault"))

  // Lifetime dependencies of non-escapable types such as the halves of a split TCP connection.
  settings.append(.enableExperimentalFeature("Lifetimes"))

  // `Builtin.stackAlloc` for temporary allocations that outlive the suspension points of an `async` function.
  settings.append(.enableExperimentalFeature("BuiltinModule"))

  // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0480-swiftpm-warning-control.md
  settings.append(.treatAllWarnings(as: .error))

  // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0458-strict-memory-safety.md
  settings.append(.strictMemorySafety())

  settings.append(
    contentsOf: availabilityMacros.map { name, value in
      .enableExperimentalFeature("AvailabilityMacro=\(name): \(value)")
    }
  )

  target.swiftSettings = settings
}
