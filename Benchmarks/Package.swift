// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "benchmarks",
  platforms: [
    .macOS("15")
  ],
  dependencies: [
    // The name is set explicitly: otherwise SwiftPM infers it from the directory name of the
    // checkout, which breaks in git worktrees (where the directory is named after the worktree).
    .package(name: "swift-platform-executors", path: "../", traits: ["ExperimentalIO"]),
    .package(url: "https://github.com/ordo-one/benchmark.git", from: "1.37.0"),
    .package(url: "https://github.com/apple/swift-collections.git", exact: "1.7.1"),
  ],
  targets: [
    .executableTarget(
      name: "IOBenchmarks",
      dependencies: [
        .product(name: "Benchmark", package: "benchmark"),
        .product(name: "PlatformExecutors", package: "swift-platform-executors"),
        .product(name: "BasicContainers", package: "swift-collections"),
      ],
      path: "Benchmarks/IOBenchmarks",
      plugins: [
        .plugin(name: "BenchmarkPlugin", package: "benchmark")
      ]
    )
  ]
)
