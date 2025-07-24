// swift-tools-version: 6.1

import PackageDescription

let package = Package(
  name: "Benchmarks",
  platforms: [
    .macOS("15.0"),
    .iOS("18.0"),
    .watchOS("11.0"),
    .tvOS("18.0"),
    .visionOS("2.0"),
  ],
  dependencies: [
    .package(path: ".."),
    .package(
      url: "https://github.com/ordo-one/package-benchmark",
      from: "1.0.0"
    ),
  ],
  targets: [
    .executableTarget(
      name: "PlatformExecutorsBenchmark",
      dependencies: [
        .product(
          name: "PlatformExecutors",
          package: "swift-platform-executors"
        ),
        .product(
          name: "Benchmark",
          package: "package-benchmark"
        ),
        .product(
          name: "BenchmarkPlugin",
          package: "package-benchmark"
        ),
      ],
      path: "Benchmarks/PlatformExecutorsBenchmark"
    )
  ]
)
