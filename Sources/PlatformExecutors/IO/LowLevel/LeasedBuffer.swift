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
/// A leased buffer that must be manually returned when you are done using it.
///
/// ```swift
/// var buffer = try await connection.read()
/// parse(buffer.bytes)
/// buffer.return()
/// ```
// TODO: Evaluate whether a backend like DPDK fits.
// TODO: Alternatively this could be modelled with custom allocators.
@safe
@available(anyAppleOS 27.0, *)
public struct LeasedBuffer: ~Copyable, @unchecked Sendable {
  /// The memory of the buffer. This is the whole capacity, and the bytes that were transferred are its start.
  private let memory: UnsafeMutableRawBufferPointer

  /// Gives the memory back to where it came from.
  private let release: @Sendable (UnsafeMutableRawBufferPointer) -> Void

  /// The number of bytes of the buffer that hold data.
  private var initializedCount: Int

  /// Whether the buffer was returned.
  // TODO: Once we have call once closures we should mark release as such and drop this bool to use discard self
  private var isReturned = false

  /// The number of bytes of the buffer that hold data.
  public var count: Int {
    self.initializedCount
  }

  /// The number of bytes that the buffer can hold.
  public var capacity: Int {
    unsafe self.memory.count
  }

  /// Whether the buffer holds no data.
  public var isEmpty: Bool {
    self.initializedCount == 0
  }

  /// The bytes that the buffer holds.
  public var bytes: RawSpan {
    @_lifetime(borrow self)
    borrowing get {
      let span = unsafe RawSpan(_unsafeBytes: UnsafeRawBufferPointer(rebasing: self.memory[..<self.initializedCount]))
      return unsafe _overrideLifetime(span, borrowing: self)
    }
  }

  /// The bytes that the buffer holds, which can be modified.
  public var mutableBytes: MutableRawSpan {
    @_lifetime(&self)
    mutating get {
      let span = unsafe MutableRawSpan(
        _unsafeBytes: UnsafeMutableRawBufferPointer(rebasing: self.memory[..<self.initializedCount])
      )
      return unsafe _overrideLifetime(span, mutating: &self)
    }
  }

  /// Adopts memory, which the lease gives back by calling the given closure.
  ///
  /// - Important: The memory has to stay valid until the closure is called, and nothing else may use it until
  ///   then. The closure can be called from any thread.
  ///
  /// - Parameters:
  ///   - memory: The memory to adopt.
  ///   - initializedCount: The number of bytes at the start of the memory that hold data.
  ///   - release: The closure that gives the memory back. It receives the memory that was adopted.
  @unsafe
  public init(
    adopting memory: UnsafeMutableRawBufferPointer,
    initializedCount: Int,
    release: @escaping @Sendable (UnsafeMutableRawBufferPointer) -> Void
  ) {
    precondition(
      initializedCount >= 0 && initializedCount <= memory.count,
      "The initialized count exceeds the memory"
    )
    unsafe self.memory = memory
    unsafe self.release = release
    self.initializedCount = initializedCount
  }

  /// A lease without any memory.
  package static func empty() -> LeasedBuffer {
    unsafe LeasedBuffer(
      adopting: .init(start: nil, count: 0),
      initializedCount: 0,
      release: { _ in }
    )
  }

  /// Arbitrarily edit the storage underlying this buffer by invoking a
  /// user-supplied closure with a mutable `OutputSpan` view over it.
  ///
  /// - Parameter body: The closure to invoke with the span.
  /// - Returns: Whatever is returned by `body`.
  public mutating func edit<Return: ~Copyable>(
    _ body: (inout OutputRawSpan) -> Return
  ) -> Return {
    var span = unsafe OutputRawSpan(buffer: self.memory, initializedCount: self.initializedCount)
    let result = body(&span)
    self.initializedCount = span.byteCount
    return result
  }

  /// Gives the buffer back to where it came from.
  public consuming func `return`() {
    unsafe self.release(self.memory)
    self.isReturned = true
  }

  deinit {
    if !self.isReturned {
      fatalError("A LeasedBuffer was destroyed without being returned.")
    }
  }
}
#endif
