// swift-tools-version: 6.2
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
    .testTarget(
      name: "PlatformExecutorsTests",
      dependencies: [
        "PlatformExecutors"
      ]
    ),
  ]
)
