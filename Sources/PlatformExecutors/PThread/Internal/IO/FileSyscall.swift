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
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

// The static methods below shadow the C functions of the same name,
// so we have to call them from the outside.
private func sysOpen(_ path: UnsafePointer<CChar>, _ flags: CInt, _ permissions: mode_t) -> CInt {
  unsafe open(path, flags, permissions)
}

private func sysClose(_ fileDescriptor: CInt) -> CInt {
  close(fileDescriptor)
}

/// Performs a syscall, retrying it while it is interrupted, and reports a failure as an ``IOError``.
///
/// Unlike ``retryingIOSyscall(blocking:where:_:)`` this reports every errno.
private func retryingFileSyscall<T: FixedWidthInteger>(_ body: () -> T) throws(IOError) -> T {
  while true {
    let result = body()
    guard result == -1 else {
      return result
    }
    let errnoCode = errno
    if errnoCode == EINTR {
      continue
    }
    throw IOError(errnoCode: errnoCode)
  }
}

/// The blocking syscalls that back the file operations of readiness based mechanisms.
enum FileSyscall {
  /// Returns the flags that open a file.
  ///
  /// - Parameter configuration: How to open the file.
  /// - Returns: The flags to pass to `open`.
  static func flags(for configuration: FileOpenConfiguration) -> CInt {
    var flags: CInt =
      switch configuration.accessMode {
      case .read: O_RDONLY
      case .write: O_WRONLY
      case .readWrite: O_RDWR
      }
    // Every file is closed on exec.
    flags |= O_CLOEXEC
    if !configuration.followSymbolicLinks { flags |= O_NOFOLLOW }
    if configuration.newFile != nil { flags |= O_CREAT }
    switch configuration.existingFile {
    case .none: flags |= O_EXCL
    case .open: break
    case .truncate: flags |= O_TRUNC
    }
    return flags
  }

  /// Returns the permissions of a file that the request creates.
  static func permissions(for configuration: FileOpenConfiguration) -> mode_t {
    mode_t((configuration.newFile?.permissions ?? .defaultsForRegularFile).rawValue)
  }

  /// Provides a null terminated copy of a path for the duration of the closure.
  ///
  /// - Parameters:
  ///   - path: The path to copy. Opening a path that contains a null byte fails with `EINVAL`.
  ///   - body: The closure to call with the pointer to the copy, which it must not use after it returns.
  /// - Returns: Whatever `body` returns.
  // TODO: Use FilePath here
  static func withCPath<Return>(
    _ path: String,
    _ body: (UnsafePointer<CChar>) async throws(IOError) -> Return
  ) async throws(IOError) -> Return {
    let utf8 = path.utf8
    guard !utf8.contains(0) else {
      throw IOError(errnoCode: EINVAL)
    }
    return try await withTemporaryAllocation(of: CChar.self, capacity: utf8.count + 1) {
      (characters: inout OutputSpan<CChar>) async throws(IOError) -> Return in
      for byte in utf8 {
        characters.append(CChar(bitPattern: byte))
      }
      characters.append(0)
      var span = characters.mutableSpan
      let pointer = span.withUnsafeMutableBufferPointer { unsafe UnsafePointer($0.baseAddress!) }
      return try await unsafe body(pointer)
    }
  }

  /// Performs a file operation, blocking the calling thread until it completes.
  ///
  /// - Parameter operation: The operation to perform. It has to be a file operation or a close.
  /// - Returns: The result of the operation in the same form as a mechanism reports it.
  static func perform(_ operation: IOOperation) -> Result<Int, IOError> {
    do {
      switch unsafe operation {
      case .openFile(let path, let flags, let permissions):
        return unsafe .success(Int(try Self.open(path: path, flags: flags, permissions: permissions)))
      case .readFile(let file, let buffer, let offset):
        return unsafe .success(try Self.read(file, into: buffer, at: offset))
      case .writeFile(let file, let buffer, let offset):
        return unsafe .success(try Self.write(file, from: buffer, at: offset))
      case .close(let file):
        try Self.close(file)
        return .success(0)
      default:
        fatalError("Only file operations are performed with blocking syscalls")
      }
    } catch {
      return .failure(error)
    }
  }

  /// Opens the file at the given path.
  ///
  /// - Parameters:
  ///   - path: The null terminated path of the file.
  ///   - flags: The flags to open the file with.
  ///   - permissions: The permissions of the file if it is created.
  /// - Returns: The file descriptor of the file.
  static func open(
    path: UnsafePointer<CChar>,
    flags: CInt,
    permissions: mode_t
  ) throws(IOError) -> CInt {
    try retryingFileSyscall {
      unsafe sysOpen(path, flags, permissions)
    }
  }

  /// Closes the file.
  ///
  /// - Parameter file: The file descriptor of the file.
  static func close(_ file: CInt) throws(IOError) {
    // This is not retried when it is interrupted: the file descriptor is released even then on Linux and
    // the BSDs, so closing it again could close one that another thread opened in the meantime.
    guard sysClose(file) == 0 else {
      throw IOError(errnoCode: errno)
    }
  }

  /// Reads from the given offset of a file into the given buffer.
  ///
  /// - Parameters:
  ///   - file: The file descriptor of the file.
  ///   - buffer: The buffer to read into.
  ///   - offset: The offset in the file to read from.
  /// - Returns: The number of bytes read, where zero means the end of the file.
  static func read(
    _ file: CInt,
    into buffer: UnsafeMutableRawBufferPointer,
    at offset: Int64
  ) throws(IOError) -> Int {
    guard let baseAddress = buffer.baseAddress, buffer.count > 0 else {
      return 0
    }
    return try retryingFileSyscall {
      unsafe pread(file, baseAddress, buffer.count, off_t(offset))
    }
  }

  /// Writes the given buffer to the given offset of a file.
  ///
  /// - Parameters:
  ///   - file: The file descriptor of the file.
  ///   - buffer: The buffer to write.
  ///   - offset: The offset in the file to write to.
  /// - Returns: The number of bytes written, which can be less than the number of bytes in the buffer.
  static func write(
    _ file: CInt,
    from buffer: UnsafeRawBufferPointer,
    at offset: Int64
  ) throws(IOError) -> Int {
    guard let baseAddress = buffer.baseAddress, buffer.count > 0 else {
      return 0
    }
    return try retryingFileSyscall {
      unsafe pwrite(file, baseAddress, buffer.count, off_t(offset))
    }
  }
}
#endif
#endif
