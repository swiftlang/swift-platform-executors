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
/// A connected TCP socket of the PThread based executors.
// TODO: Make this `~Copyable` again once we have ~Copyable existentials
@available(anyAppleOS 27.0, *)
public struct PThreadTCPConnection: Sendable {
  /// The file descriptor of the socket.
  package var fileDescriptor: CInt

  /// The index of the executor in the pool that services the socket.
  internal var executorIndex: Int

  internal init(fileDescriptor: CInt, executorIndex: Int) {
    self.fileDescriptor = fileDescriptor
    self.executorIndex = executorIndex
  }

  /// Takes the file descriptor out of the socket, giving up ownership of it.
  internal consuming func takeFileDescriptor() -> CInt {
    let fileDescriptor = self.fileDescriptor
    // discard self
    return fileDescriptor
  }

  // deinit {
  //   fatalError("A PThreadTCPConnection was destroyed without being closed.")
  // }
}
#endif
#endif
