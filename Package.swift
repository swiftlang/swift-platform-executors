// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "SwiftPlatformExecutors",
  platforms: [
    .macOS(.v26)
  ],
  products: [
    .library(
      name: "PlatformExecutors",
      targets: [
        "PlatformExecutors"
      ]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-collections.git",
             from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-docc-plugin",
             from: "1.0.0"),
  ],
  targets: [
    .target(
      name: "PlatformExecutors",
      dependencies: [
        .product(name: "DequeModule", package: "swift-collections"),
        .target(name: "CPlatformExecutors"),
      ]
    ),
    .target(
      name: "CPlatformExecutors",
      cSettings: [
        .define("_GNU_SOURCE")
      ]
    ),
    .testTarget(
      name: "PlatformExecutorsTests",
      dependencies: [
        "PlatformExecutors"
      ]
    ),
  ]
)
