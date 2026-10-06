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

#if os(Linux) || os(Android) || os(FreeBSD) || canImport(Darwin)
/// The events that a registration is interested in.
struct ReadinessInterest: OptionSet, Hashable {
  var rawValue: UInt8

  /// The file descriptor became readable.
  static var read: ReadinessInterest { ReadinessInterest(rawValue: 1 << 0) }

  /// The file descriptor became writable.
  static var write: ReadinessInterest { ReadinessInterest(rawValue: 1 << 1) }
}

/// An event that a readiness based backend reported for a registered file descriptor.
struct ReadinessEvent {
  /// The identifier of the registration that this event belongs to.
  var registrationID: UInt32

  /// The file descriptor that this event belongs to.
  var fileDescriptor: CInt

  /// Whether the file descriptor is readable.
  ///
  /// This is also set when the peer closed its side of the connection since the read that follows reports
  /// the end of the stream.
  var isReadable: Bool

  /// Whether the file descriptor is writable.
  var isWritable: Bool

  /// Whether the file descriptor has a pending error.
  var isError: Bool
}
#endif
