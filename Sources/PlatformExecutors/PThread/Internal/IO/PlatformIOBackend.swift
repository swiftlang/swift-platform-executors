//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if os(Linux) || os(Android) || os(FreeBSD) || canImport(Darwin) || os(WASI)
/// The I/O mechanism that a platform uses.
///
/// This is the one place that decides which default mechanism a platform uses.
#if canImport(Darwin)
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
typealias PlatformIOBackend = KQueueReadinessBackend
#elseif canImport(Glibc)
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
typealias PlatformIOBackend = EpollReadinessBackend
#elseif os(WASI)
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
typealias PlatformIOBackend = ConditionSelectorBackend
#else
#error("Unsupported platform")
#endif
#endif
