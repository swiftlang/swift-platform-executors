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
/// The permissions of a file.
///
/// These are the bits of the `mode` of `open(2)`.
@available(anyAppleOS 27.0, *)
public struct FilePermissions: OptionSet, Hashable, Sendable {
  public var rawValue: UInt16

  public init(rawValue: UInt16) {
    self.rawValue = rawValue
  }

  public static var ownerRead: FilePermissions { FilePermissions(rawValue: 0o400) }
  public static var ownerWrite: FilePermissions { FilePermissions(rawValue: 0o200) }
  public static var ownerExecute: FilePermissions { FilePermissions(rawValue: 0o100) }
  public static var groupRead: FilePermissions { FilePermissions(rawValue: 0o040) }
  public static var groupWrite: FilePermissions { FilePermissions(rawValue: 0o020) }
  public static var groupExecute: FilePermissions { FilePermissions(rawValue: 0o010) }
  public static var otherRead: FilePermissions { FilePermissions(rawValue: 0o004) }
  public static var otherWrite: FilePermissions { FilePermissions(rawValue: 0o002) }
  public static var otherExecute: FilePermissions { FilePermissions(rawValue: 0o001) }

  public static var ownerReadWrite: FilePermissions { [.ownerRead, .ownerWrite] }
  public static var ownerReadWriteExecute: FilePermissions { [.ownerRead, .ownerWrite, .ownerExecute] }

  /// Read and write for the owner and read for everyone else, the permissions of a new file by default.
  public static var defaultsForRegularFile: FilePermissions { [.ownerReadWrite, .groupRead, .otherRead] }
}
#endif
