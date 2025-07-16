// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "SwiftPlatformExecutors",
  products: [
    .library(
      name: "Win32NativeExecutors",
      targets: ["Win32NativeExecutors"]),
  ],
  targets: [
    .target(
      name: "Win32NativeExecutors"),
    .testTarget(
      name: "Win32NativeExecutorsTests",
      dependencies: [
        "Win32NativeExecutors",
        .product(name: "Testing", package: "swift-testing"),
      ]
    ),
  ]
)
