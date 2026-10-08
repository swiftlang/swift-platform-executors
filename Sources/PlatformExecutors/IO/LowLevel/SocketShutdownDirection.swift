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
/// The direction of a socket that is shut down.
public enum SocketShutdownDirection: Sendable, Hashable {
  /// Shuts down the read direction.
  ///
  /// Any data that the peer sends afterwards is discarded.
  case read

  /// Shuts down the write direction.
  ///
  /// The peer observes this as the end of the stream once it has received all data that is still in flight.
  case write

  /// Shuts down both the read and the write direction.
  case readWrite
}
#endif
