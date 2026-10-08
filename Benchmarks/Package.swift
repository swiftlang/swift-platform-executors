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
    .package(url: "https://github.com/ordo-one/benchmark.git", from: "1.36.4"),
  ],
  targets: [
    .executableTarget(
      name: "IOBenchmarks",
      dependencies: [
        .product(name: "Benchmark", package: "benchmark"),
        .product(name: "PlatformExecutors", package: "swift-platform-executors"),
      ],
      path: "Benchmarks/IOBenchmarks",
      plugins: [
        .plugin(name: "BenchmarkPlugin", package: "benchmark")
      ]
    )
  ]
)
