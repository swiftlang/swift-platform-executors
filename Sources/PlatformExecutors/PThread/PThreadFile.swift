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
/// An open file of the PThread based executors.
// TODO: Make this `~Copyable` again once we have ~Copyable existentials
@available(anyAppleOS 27.0, *)
public struct PThreadFile: Sendable {
  /// The file descriptor of the file.
  package var fileDescriptor: CInt

  /// The index of the executor in the pool that services the file descriptor.
  internal var executorIndex: Int

  internal init(fileDescriptor: CInt, executorIndex: Int) {
    self.fileDescriptor = fileDescriptor
    self.executorIndex = executorIndex
  }
}
#endif
#endif
