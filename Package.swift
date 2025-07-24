// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "PlatformExecutors",
  platforms: [.macOS("26.0")],
  products: [
    .library(
      name: "PlatformExecutors",
      targets: [
        "PlatformExecutors"
      ]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-docc-plugin",
             from: "1.0.0"),
  ],
  targets: [
    .target(
      name: "PlatformExecutors",
      dependencies: [
        .target(name: "CPlatformExecutors")
      ],
      swiftSettings: [
        .unsafeFlags([
          "-Xfrontend",
          "-disable-availability-checking"
        ])
      ],
    ),
    .target(
      name: "CPlatformExecutors",
      cSettings: [
        .define("_GNU_SOURCE")
      ]
    ),
    .executableTarget(
      name: "PThreadExecutorsExample",
      dependencies: [
        .target(name: "PlatformExecutors")
      ],
      path: "Examples/PThreadExecutors",
    ),
    .testTarget(
      name: "PlatformExecutorsTests",
      dependencies: [
        "PlatformExecutors"
      ]
    ),
  ]
)
