// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "PlatformExecutors",
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
      ]
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
