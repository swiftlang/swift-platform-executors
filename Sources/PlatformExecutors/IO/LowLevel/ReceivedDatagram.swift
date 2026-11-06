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
/// A datagram that a scheduler received into one of its buffers.
@available(anyAppleOS 27.0, *)
@frozen
public struct ReceivedDatagram: ~Copyable, Sendable {
  /// The buffer with the bytes of the datagram, which has to be returned.
  public var buffer: LeasedBuffer

  /// The address of the sender.
  public var sender: SocketAddress

  public init(buffer: consuming LeasedBuffer, sender: SocketAddress) {
    self.buffer = buffer
    self.sender = sender
  }
}
#endif
