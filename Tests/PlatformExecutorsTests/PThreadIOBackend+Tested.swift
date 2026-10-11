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

#if os(Linux) || os(FreeBSD) || canImport(Darwin)

@_spi(ExperimentalScheduling) @_spi(ConcurrencyExecutors) @_spi(ExperimentalCustomExecutors) import PlatformExecutors

extension PThreadIOBackend {
  /// The mechanisms that the tests run the PThread based executors on.
  static let tested: [PThreadIOBackend] = {
    #if canImport(Darwin)
    let backends: [PThreadIOBackend] = [.kqueue]
    #elseif canImport(Glibc)
    var backends: [PThreadIOBackend] = [.epoll]
    #if ExperimentalIOUring
    do {
      try PThreadIOBackend.ioUring.checkAvailability()
      backends.append(.ioUring)
    } catch {
      print("The tests skip the io_uring backend, which is not available: \(error)")
    }
    #endif
    #else
    let backends: [PThreadIOBackend] = [.platformDefault]
    #endif
    print("The tests run the PThread based executors on the I/O backends: \(backends)")
    return backends
  }()
}
#endif
