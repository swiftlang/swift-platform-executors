//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2024 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if os(Linux) || os(Android) || os(FreeBSD) || canImport(Darwin) || os(WASI)

#if os(WASI)
import CPlatformExecutors
import WASILibc
import wasi_pthread

private let sys_pthread_getname_np = CPlatformExecutors_pthread_getname_np
private let sys_pthread_setname_np = CPlatformExecutors_pthread_setname_np
private typealias ThreadDestructor = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
#elseif os(Linux) || os(Android)
import CPlatformExecutors

private let sys_pthread_getname_np = unsafe CPlatformExecutors_pthread_getname_np
private let sys_pthread_setname_np = unsafe CPlatformExecutors_pthread_setname_np
#if os(Android)
private typealias ThreadDestructor = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer
#else
private typealias ThreadDestructor = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
#endif
#elseif canImport(Darwin)
import CPlatformExecutors
import Darwin

private let sys_pthread_getname_np = unsafe pthread_getname_np
// Emulate the same method signature as pthread_setname_np on Linux.
private func sys_pthread_setname_np(
  _ p: pthread_t,
  _ pointer: UnsafePointer<Int8>
) -> Int32 {
  unsafe assert(pthread_equal(pthread_self(), p) != 0)
  unsafe pthread_setname_np(pointer)
  // Will never fail on macOS so just return 0 which will be used on linux to signal it not failed.
  return 0
}
private typealias ThreadDestructor = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?

#endif

/// Runs `body` with specified thread attributes.
///
/// - Parameters:
///   - stackSize: The requested stack size in bytes, or nil to use the default stack size.
///     The passed value will be normalized to the platform's minimum and page size.
///   - body: The closure that creates the thread using the passed attributes
/// - Returns: The result of `body`, or the error code of the failed `pthread_attr_*` call
private func withThreadAttributes(
  stackSize: Int?,
  _ body: (UnsafePointer<pthread_attr_t>?) -> CInt
) -> CInt {
  guard let stackSize else {
    return body(nil)
  }
  var attr = pthread_attr_t()
  var result = unsafe pthread_attr_init(&attr)
  guard result == 0 else {
    return result
  }
  defer { unsafe pthread_attr_destroy(&attr) }
  result = unsafe pthread_attr_setstacksize(
    &attr,
    CPlatformExecutors_pthread_normalized_stack_size(stackSize)
  )
  guard result == 0 else {
    return result
  }
  return unsafe body(&attr)
}

private func sysPthread_create(
  handle: UnsafeMutablePointer<pthread_t?>,
  stackSize: Int?,
  destructor: @escaping ThreadDestructor,
  args: UnsafeMutableRawPointer?
) -> CInt {
  #if canImport(Darwin)
  return unsafe withThreadAttributes(stackSize: stackSize) { attr in
    unsafe pthread_create(handle, attr, destructor, args)
  }
  #elseif os(WASI)
  // wasi-libc's `pthread_t` is a pointer; the shim adds the explicit stack
  // (wasi-libc's default thread stack is small and wasm has no guard page).
  var handleWASI: pthread_t? = nil
  let result = CPlatformExecutors_wasi_pthread_create(
    &handleWASI,
    destructor,
    args,
    stackSize.map(CPlatformExecutors_pthread_normalized_stack_size) ?? 0
  )
  handle.pointee = handleWASI
  return result
  #else
  #if canImport(Musl)
  var handleLinux: OpaquePointer? = nil
  #else
  var handleLinux = pthread_t()
  #endif
  let result = unsafe withThreadAttributes(stackSize: stackSize) { attr in
    unsafe pthread_create(
      &handleLinux,
      attr,
      destructor,
      args
    )
  }
  unsafe handle.pointee = handleLinux
  return result
  #endif
}

enum PThread {
  /// The handle of a thread.
  ///
  /// A `pthread_t` is a pointer on some platforms and an integer on others so this wraps it to be memory safe on all of them.
  @safe
  struct ThreadHandle: @unchecked Sendable {
    /// The bits of the `pthread_t`.
    fileprivate var bits: UInt

    /// Creates a handle of the calling thread.
    fileprivate init() {
      self.bits = 0
      withUnsafeMutableBytes(of: &self.bits) { unsafe $0.storeBytes(of: pthread_self(), as: pthread_t.self) }
    }

    /// Creates a handle of the thread that `pthread_create` stored.
    fileprivate init(created thread: UnsafePointer<pthread_t?>) {
      self.bits = withUnsafeBytes(of: unsafe thread.pointee!) { unsafe $0.load(as: UInt.self) }
    }

    @unsafe
    fileprivate var rawValue: pthread_t {
      withUnsafeBytes(of: self.bits) { unsafe $0.load(as: pthread_t.self) }
    }
  }
  typealias ThreadSpecificKey = pthread_key_t
  #if canImport(Darwin)
  typealias ThreadSpecificKeyDestructor = @convention(c) (UnsafeMutableRawPointer) -> Void
  #else
  typealias ThreadSpecificKeyDestructor = @convention(c) (UnsafeMutableRawPointer?) -> Void
  #endif

  static func threadName(_ thread: PThread.ThreadHandle) -> String? {
    // 64 bytes should be good enough as on Linux the limit is usually 16
    // and it's very unlikely a user will ever set something longer
    // anyway.
    var chars: [CChar] = Array(repeating: 0, count: 64)
    return chars.withUnsafeMutableBufferPointer { ptr in
      guard unsafe sys_pthread_getname_np(thread.rawValue, ptr.baseAddress!, ptr.count) == 0 else {
        return nil
      }

      let buffer: UnsafeRawBufferPointer =
        unsafe UnsafeRawBufferPointer(UnsafeBufferPointer<CChar>(rebasing: ptr.prefix { $0 != 0 }))
      return unsafe String(decoding: buffer, as: Unicode.UTF8.self)
    }
  }

  static func run(
    stackSize: Int?,
    args: Box<Thread.ThreadBoxValue>
  ) -> PThread.ThreadHandle {
    var handle: pthread_t? = nil
    let argv0 = unsafe Unmanaged.passRetained(args).toOpaque()
    let res = unsafe sysPthread_create(
      handle: &handle,
      stackSize: stackSize,
      destructor: {
        // Cast to UnsafeMutableRawPointer? and force unwrap to make the
        // same code work on macOS and Linux.
        let boxed = unsafe Unmanaged<Thread.ThreadBox>
          .fromOpaque(($0 as UnsafeMutableRawPointer?)!)
          .takeRetainedValue()
        let (body, name) = (boxed.value.body, boxed.value.name)
        let hThread = unsafe ThreadHandle().rawValue

        if let name = name {
          let maximumThreadNameLength: Int
          #if os(Linux) || os(Android) || os(WASI)
          maximumThreadNameLength = 15
          #else
          maximumThreadNameLength = .max
          #endif
          name.prefix(maximumThreadNameLength).withCString { namePtr in
            // this is non-critical so we ignore the result here, we've seen
            // EPERM in containers.
            _ = unsafe sys_pthread_setname_np(hThread, namePtr)
          }
        }

        body()

        #if os(Android)
        return UnsafeMutableRawPointer(bitPattern: 0xdeadbee)!
        #else
        return nil
        #endif
      },
      args: unsafe argv0
    )
    precondition(res == 0, "Unable to create thread: \(res)")
    return unsafe ThreadHandle(created: &handle)
  }

  static func isCurrentThread(_ thread: PThread.ThreadHandle) -> Bool {
    #if os(WASI)
    // wasi-libc's pthread_equal is a function-like macro (pointer identity).
    return unsafe thread.rawValue == ThreadHandle().rawValue
    #else
    return unsafe pthread_equal(thread.rawValue, ThreadHandle().rawValue) != 0
    #endif
  }

  static var currentThread: PThread.ThreadHandle {
    return ThreadHandle()
  }

  /// An identity of the calling thread that fits into an atomic.
  static var currentThreadIdentity: UInt {
    return ThreadHandle().bits
  }

  static func compareThreads(_ lhs: PThread.ThreadHandle, _ rhs: PThread.ThreadHandle) -> Bool {
    #if os(WASI)
    return unsafe lhs.rawValue == rhs.rawValue
    #else
    return unsafe pthread_equal(lhs.rawValue, rhs.rawValue) != 0
    #endif
  }

  static func joinThread(_ thread: PThread.ThreadHandle) {
    let result = unsafe pthread_join(thread.rawValue, nil)
    precondition(result == 0, "pthread_join failed with error code: \(result)")
  }
}

#endif
