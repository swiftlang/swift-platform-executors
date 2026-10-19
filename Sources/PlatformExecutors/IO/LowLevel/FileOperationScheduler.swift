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
/// A scheduler that can perform file operations.
@available(anyAppleOS 27.0, *)
public protocol FileOperationScheduler<FileHandle>: OperationScheduler {
  /// The handle identifying an open file of this scheduler.
  // TODO: Make the handle `~Copyable` again
  // TODO: Take a portable path type once there is one.
  associatedtype FileHandle: Sendable

  /// Opens the file at the given path.
  ///
  /// - Parameters:
  ///   - path: The path of the file.
  ///   - configuration: How to open the file.
  /// - Returns: The open file.
  func open(
    path: String,
    configuration: FileOpenConfiguration
  ) async throws(IOError) -> FileHandle

  /// Reads once from the given offset of a file into the free capacity of the given buffer.
  ///
  /// The bytes are appended to the buffer. A read can return fewer bytes than the free capacity of the
  /// buffer.
  ///
  /// - Parameters:
  ///   - file: The file to read from.
  ///   - buffer: The buffer to read into.
  ///   - offset: The offset in the file to read from.
  /// - Returns: The number of bytes read. Zero indicates that the offset is at or behind the end of the file,
  ///   or that the buffer has no free capacity.
  func read(
    file: borrowing FileHandle,
    into buffer: inout OutputRawSpan,
    at offset: Int64
  ) async throws(IOError) -> Int

  /// Writes the given buffer to the given offset of a file.
  ///
  /// - Parameters:
  ///   - file: The file to write to.
  ///   - buffer: The buffer to write from.
  ///   - offset: The offset in the file to write to.
  /// - Returns: The number of bytes written. This can be less than the number of bytes in the buffer.
  func write(
    file: borrowing FileHandle,
    from buffer: RawSpan,
    at offset: Int64
  ) async throws(IOError) -> Int

  /// Closes a file.
  ///
  /// - Parameter file: The file to close.
  func close(file: consuming FileHandle) async throws(IOError)
}

/// How a scheduler opens a file.
///
/// The high-level file types turn their open options into this, so a scheduler only deals with one
/// description.
@available(anyAppleOS 27.0, *)
public struct FileOpenConfiguration: Hashable, Sendable {
  /// How the file is accessed.
  public enum AccessMode: Hashable, Sendable {
    /// The file can only be read from.
    case read

    /// The file can only be written to.
    case write

    /// The file can be read from and written to.
    case readWrite
  }

  /// What happens if the file exists already.
  public enum ExistingFile: Hashable, Sendable {
    /// Opening fails, so the file has to be created.
    case none

    /// The file is opened and keeps its content.
    case open

    /// The file is opened and its content is dropped.
    case truncate
  }

  /// The permissions of a file.
  public struct Permissions: OptionSet, Hashable, Sendable {
    public var rawValue: UInt16

    public init(rawValue: UInt16) {
      self.rawValue = rawValue
    }

    public static var ownerRead: Permissions { Permissions(rawValue: 0o400) }
    public static var ownerWrite: Permissions { Permissions(rawValue: 0o200) }
    public static var ownerExecute: Permissions { Permissions(rawValue: 0o100) }
    public static var groupRead: Permissions { Permissions(rawValue: 0o040) }
    public static var groupWrite: Permissions { Permissions(rawValue: 0o020) }
    public static var groupExecute: Permissions { Permissions(rawValue: 0o010) }
    public static var otherRead: Permissions { Permissions(rawValue: 0o004) }
    public static var otherWrite: Permissions { Permissions(rawValue: 0o002) }
    public static var otherExecute: Permissions { Permissions(rawValue: 0o001) }

    public static var ownerReadWrite: Permissions { [.ownerRead, .ownerWrite] }
    public static var ownerReadWriteExecute: Permissions { [.ownerRead, .ownerWrite, .ownerExecute] }

    /// Read and write for the owner and read for everyone else, the permissions of a new file by default.
    public static var defaultsForRegularFile: Permissions { [.ownerReadWrite, .groupRead, .otherRead] }
  }

  /// How a file that doesn't exist is created.
  public struct NewFile: Hashable, Sendable {
    /// The permissions of the new file, or `nil` for ``Permissions/defaultsForRegularFile``. The
    /// process's `umask` is applied.
    public var permissions: Permissions?

    public init(permissions: Permissions? = nil) {
      self.permissions = permissions
    }
  }

  /// How the file is accessed.
  public var accessMode: AccessMode

  /// What happens if the file exists already.
  public var existingFile: ExistingFile

  /// How a file that doesn't exist is created, or `nil` if it isn't created.
  public var newFile: NewFile?

  /// Whether the last component of the path is followed if it is a symbolic link. If it is not and the last
  /// component is a symbolic link, opening the file fails.
  public var followSymbolicLinks: Bool

  public init(
    accessMode: AccessMode,
    existingFile: ExistingFile,
    newFile: NewFile?,
    followSymbolicLinks: Bool
  ) {
    self.accessMode = accessMode
    self.existingFile = existingFile
    self.newFile = newFile
    self.followSymbolicLinks = followSymbolicLinks
  }
}
#endif
