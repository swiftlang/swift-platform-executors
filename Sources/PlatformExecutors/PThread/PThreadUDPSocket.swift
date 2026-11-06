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

#if ExperimentalIO
#if os(Linux) || os(Android) || os(FreeBSD) || canImport(Darwin)
/// A UDP socket of a ``PThreadExecutor`` or a ``PThreadTaskExecutor``.
@available(anyAppleOS 27.0, *)
public struct PThreadUDPSocket: Sendable {
  /// The file descriptor of the socket.
  package var fileDescriptor: CInt

  internal init(fileDescriptor: CInt) {
    self.fileDescriptor = fileDescriptor
  }

  /// Takes the file descriptor out of the socket, giving up ownership of it.
  internal consuming func takeFileDescriptor() -> CInt {
    let fileDescriptor = self.fileDescriptor
    // discard self
    return fileDescriptor
  }
}
#endif
#endif
