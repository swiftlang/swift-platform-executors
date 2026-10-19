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
/// An open file that can be read from and written to.
///
/// A file is opened with ``open(path:options:)``. If a file is only read from or only written to, open it
/// as a ``Readable`` or a ``Writable`` instead.
///
/// A file uniquely owns the underlying platform resource, so it cannot be copied. It must be closed
/// explicitly with ``close()`` since closing is an asynchronous operation, and destroying a file without
/// closing it traps.
///
/// ```swift
/// let file = try await File.open(path: "/tmp/greeting.txt", options: .newFile(replaceExisting: true))
/// try await file.write(from: greeting.bytes, at: 0)
/// let count = try await file.read(into: &contents, at: 0)
/// try await file.close()
/// ```
@available(anyAppleOS 27.0, *)
public struct File: ~Copyable, Sendable {
  private var core: FileCore

  private init(core: consuming FileCore) {
    self.core = core
  }

  /// Opens a file for reading and writing.
  ///
  /// - Parameters:
  ///   - path: The path of the file.
  ///   - options: How to open the file. By default a new file is created, and opening fails if the file exists
  ///     already.
  /// - Returns: The open file.
  public static func open(
    path: String,
    options: OpenOptions = .newFile(replaceExisting: false)
  ) async throws(IOError) -> File {
    File(core: try await FileCore.open(path: path, configuration: options.configuration(accessMode: .readWrite)))
  }

  /// Reads once from the given offset of the file into the free capacity of the given buffer.
  ///
  /// The bytes are appended to the buffer. A read can return fewer bytes than the free capacity of the buffer.
  ///
  /// - Parameters:
  ///   - buffer: The buffer to read into.
  ///   - offset: The offset in the file to read from.
  /// - Returns: The number of bytes read. Zero indicates that the offset is at or behind the end of the file,
  ///   or that the buffer has no free capacity.
  @discardableResult
  public borrowing func read(into buffer: inout OutputRawSpan, at offset: Int64) async throws(IOError) -> Int {
    try await self.core.read(into: &buffer, at: offset)
  }

  /// Writes all bytes of the given buffer to the given offset of the file.
  ///
  /// - Parameters:
  ///   - buffer: The buffer to write.
  ///   - offset: The offset in the file to write to.
  public borrowing func write(from buffer: RawSpan, at offset: Int64) async throws(IOError) {
    try await self.core.write(from: buffer, at: offset)
  }

  /// Closes the file.
  public consuming func close() async throws(IOError) {
    try await self.core.close()
  }
}

// MARK: - Options

@available(anyAppleOS 27.0, *)
extension File {
  /// The options to open a file for reading and writing with, which are the options of a ``Writable``.
  public typealias OpenOptions = Writable.OpenOptions
}

// MARK: - Readable

@available(anyAppleOS 27.0, *)
extension File {
  /// An open file that can only be read from.
  ///
  /// Like a ``File`` it is closed explicitly with ``close()``, and destroying it without closing it traps.
  public struct Readable: ~Copyable, Sendable {
    /// The options to open a file for reading with.
    public struct OpenOptions: Hashable, Sendable {
      /// Whether the last component of the path is followed if it is a symbolic link. If it is not and the last
      /// component is a symbolic link, opening the file fails.
      public var followSymbolicLinks: Bool

      /// Creates the options to open a file for reading with.
      ///
      /// - Parameter followSymbolicLinks: Whether symbolic links are followed. Defaults to `true`.
      public init(followSymbolicLinks: Bool = true) {
        self.followSymbolicLinks = followSymbolicLinks
      }
    }

    private var core: FileCore

    private init(core: consuming FileCore) {
      self.core = core
    }

    /// Opens a file for reading.
    ///
    /// - Parameters:
    ///   - path: The path of the file.
    ///   - options: How to open the file.
    /// - Returns: The open file.
    public static func open(
      path: String,
      options: OpenOptions = OpenOptions()
    ) async throws(IOError) -> Readable {
      let configuration = FileOpenConfiguration(
        accessMode: .read,
        existingFile: .open,
        newFile: nil,
        followSymbolicLinks: options.followSymbolicLinks
      )
      return Readable(core: try await FileCore.open(path: path, configuration: configuration))
    }

    /// Reads once from the given offset of the file into the free capacity of the given buffer.
    ///
    /// The bytes are appended to the buffer. A read can return fewer bytes than the free capacity of the
    /// buffer.
    ///
    /// - Parameters:
    ///   - buffer: The buffer to read into.
    ///   - offset: The offset in the file to read from.
    /// - Returns: The number of bytes read. Zero indicates that the offset is at or behind the end of the file,
    ///   or that the buffer has no free capacity.
    @discardableResult
    public borrowing func read(into buffer: inout OutputRawSpan, at offset: Int64) async throws(IOError) -> Int {
      try await self.core.read(into: &buffer, at: offset)
    }

    /// Closes the file.
    public consuming func close() async throws(IOError) {
      try await self.core.close()
    }
  }
}

// MARK: - Writable

@available(anyAppleOS 27.0, *)
extension File {
  /// An open file that can only be written to.
  ///
  /// Like a ``File`` it is closed explicitly with ``close()``, and destroying it without closing it traps.
  public struct Writable: ~Copyable, Sendable {
    /// The options to open a file for writing, or for reading and writing, with.
    ///
    /// Use these to create commonly used sets of options:
    /// - ``newFile(replaceExisting:permissions:)`` creates a new file, optionally replacing one that exists
    ///   already.
    /// - ``modifyFile(createIfNecessary:permissions:)`` modifies an existing file, optionally creating it if
    ///   it doesn't exist.
    public struct OpenOptions: Hashable, Sendable {
      /// What happens if the file exists already.
      public enum ExistingFile: Hashable, Sendable {
        /// Opening fails, so the file has to be created.
        case none

        /// The file is opened and keeps its content.
        case open

        /// The file is opened and its content is dropped.
        case truncate
      }

      /// How a file that doesn't exist is created.
      public struct NewFile: Hashable, Sendable {
        /// The permissions of the new file, or `nil` for ``FilePermissions/defaultsForRegularFile``. The
        /// process's `umask` is applied.
        public var permissions: FilePermissions?

        public init(permissions: FilePermissions? = nil) {
          self.permissions = permissions
        }
      }

      /// What happens if the file exists already.
      public var existingFile: ExistingFile

      /// How a file that doesn't exist is created, or `nil` if opening fails for such a file.
      public var newFile: NewFile?

      /// Whether the last component of the path is followed if it is a symbolic link. If it is not and the last
      /// component is a symbolic link, opening the file fails.
      public var followSymbolicLinks: Bool

      /// Creates the options to open a file for writing with.
      ///
      /// - Parameters:
      ///   - existingFile: What happens if the file exists already. ``ExistingFile/none`` requires `newFile`,
      ///     since opening could never succeed otherwise.
      ///   - newFile: How a file that doesn't exist is created, or `nil` if it isn't.
      ///   - followSymbolicLinks: Whether symbolic links are followed. Defaults to `true`.
      public init(
        existingFile: ExistingFile,
        newFile: NewFile?,
        followSymbolicLinks: Bool = true
      ) {
        precondition(
          existingFile != .none || newFile != nil,
          "Opening a file can't succeed if it neither opens an existing file nor creates a new one"
        )
        self.existingFile = existingFile
        self.newFile = newFile
        self.followSymbolicLinks = followSymbolicLinks
      }

      /// Creates a new file.
      ///
      /// - Parameters:
      ///   - replaceExisting: Whether the content of a file that exists already is replaced. If it is not,
      ///     opening fails for a file that exists already.
      ///   - permissions: The permissions of the new file, or `nil` for
      ///     ``FilePermissions/defaultsForRegularFile``.
      public static func newFile(
        replaceExisting: Bool,
        permissions: FilePermissions? = nil
      ) -> OpenOptions {
        OpenOptions(
          existingFile: replaceExisting ? .truncate : .none,
          newFile: NewFile(permissions: permissions)
        )
      }

      /// Opens a file that exists already to modify it.
      ///
      /// - Parameters:
      ///   - createIfNecessary: Whether a file is created if it doesn't exist. If it is not, opening fails for
      ///     a file that doesn't exist.
      ///   - permissions: The permissions of the new file, or `nil` for
      ///     ``FilePermissions/defaultsForRegularFile``. This is ignored if `createIfNecessary` is `false`.
      public static func modifyFile(
        createIfNecessary: Bool,
        permissions: FilePermissions? = nil
      ) -> OpenOptions {
        OpenOptions(
          existingFile: .open,
          newFile: createIfNecessary ? NewFile(permissions: permissions) : nil
        )
      }

      fileprivate func configuration(accessMode: FileOpenConfiguration.AccessMode) -> FileOpenConfiguration {
        let existingFile: FileOpenConfiguration.ExistingFile =
          switch self.existingFile {
          case .none: .none
          case .open: .open
          case .truncate: .truncate
          }
        return FileOpenConfiguration(
          accessMode: accessMode,
          existingFile: existingFile,
          newFile: self.newFile.map {
            FileOpenConfiguration.NewFile(
              permissions: $0.permissions.map { FileOpenConfiguration.Permissions(rawValue: $0.rawValue) }
            )
          },
          followSymbolicLinks: self.followSymbolicLinks
        )
      }
    }

    private var core: FileCore

    private init(core: consuming FileCore) {
      self.core = core
    }

    /// Opens a file for writing.
    ///
    /// - Parameters:
    ///   - path: The path of the file.
    ///   - options: How to open the file. By default a new file is created, and opening fails if the file exists
    ///     already.
    /// - Returns: The open file.
    public static func open(
      path: String,
      options: OpenOptions = .newFile(replaceExisting: false)
    ) async throws(IOError) -> Writable {
      Writable(core: try await FileCore.open(path: path, configuration: options.configuration(accessMode: .write)))
    }

    /// Writes all bytes of the given buffer to the given offset of the file.
    ///
    /// - Parameters:
    ///   - buffer: The buffer to write.
    ///   - offset: The offset in the file to write to.
    public borrowing func write(from buffer: RawSpan, at offset: Int64) async throws(IOError) {
      try await self.core.write(from: buffer, at: offset)
    }

    /// Closes the file.
    public consuming func close() async throws(IOError) {
      try await self.core.close()
    }
  }
}

// MARK: - Shared implementation

/// What the file types have in common: the scheduler that services the file and the scheduler's handle of it.
@available(anyAppleOS 27.0, *)
struct FileCore: ~Copyable, Sendable {
  /// The scheduler that services the file.
  private let scheduler: any FileOperationScheduler

  /// The scheduler's handle of the file, or `nil` once the file is closed.
  private var file: (any Sendable)?

  private init<Scheduler: FileOperationScheduler>(
    scheduler: Scheduler,
    file: Scheduler.FileHandle
  ) {
    self.scheduler = scheduler
    self.file = file
  }

  static func open(path: String, configuration: FileOpenConfiguration) async throws(IOError) -> FileCore {
    guard
      let scheduler = OperationSchedulerPreference.resolve(as: (any FileOperationScheduler).self)
    else {
      fatalError(
        "No operation scheduler for files found. Use withOperationScheduler or a task executor preference."
      )
    }
    return try await Self.open(path: path, configuration: configuration, on: scheduler)
  }

  private static func open<Scheduler: FileOperationScheduler>(
    path: String,
    configuration: FileOpenConfiguration,
    on scheduler: Scheduler
  ) async throws(IOError) -> FileCore {
    let file = try await scheduler.open(path: path, configuration: configuration)
    return FileCore(scheduler: scheduler, file: file)
  }

  borrowing func read(into buffer: inout OutputRawSpan, at offset: Int64) async throws(IOError) -> Int {
    try await Self.read(into: &buffer, at: offset, file: self.file, on: self.scheduler)
  }

  private static func read<Scheduler: FileOperationScheduler>(
    into buffer: inout OutputRawSpan,
    at offset: Int64,
    file: (any Sendable)?,
    on scheduler: Scheduler
  ) async throws(IOError) -> Int {
    try await scheduler.read(file: Self.file(file, of: scheduler), into: &buffer, at: offset)
  }

  borrowing func write(from buffer: RawSpan, at offset: Int64) async throws(IOError) {
    try await Self.write(from: buffer, at: offset, file: self.file, on: self.scheduler)
  }

  private static func write<Scheduler: FileOperationScheduler>(
    from buffer: RawSpan,
    at offset: Int64,
    file: (any Sendable)?,
    on scheduler: Scheduler
  ) async throws(IOError) {
    let file = Self.file(file, of: scheduler)
    var remaining = buffer
    var offset = offset
    while !remaining.isEmpty {
      let count = try await scheduler.write(file: file, from: remaining, at: offset)
      remaining = remaining.extracting(droppingFirst: count)
      offset += Int64(count)
    }
  }

  consuming func close() async throws(IOError) {
    try await Self.close(self.file.take(), on: self.scheduler)
  }

  private static func close<Scheduler: FileOperationScheduler>(
    _ file: (any Sendable)?,
    on scheduler: Scheduler
  ) async throws(IOError) {
    let file = file as! Scheduler.FileHandle
    try await withTaskCancellationShield { () async throws(IOError) -> Void in
      try await scheduler.close(file: file)
    }
  }

  /// Returns the handle of the file as the handle type of the given scheduler.
  ///
  /// - Parameters:
  ///   - file: The erased handle of the file.
  ///   - scheduler: The scheduler that services the file.
  private static func file<Scheduler: FileOperationScheduler>(
    _ file: (any Sendable)?,
    of scheduler: Scheduler
  ) -> Scheduler.FileHandle {
    // The handle was created by this scheduler, and it is only `nil` once
    // the file is closed, which consumes it. So the cast cannot fail.
    file as! Scheduler.FileHandle
  }

  deinit {
    if self.file != nil {
      fatalError("A file was destroyed without being closed.")
    }
  }
}
#endif
