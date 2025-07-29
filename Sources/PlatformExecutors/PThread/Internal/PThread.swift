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

#if os(Linux) || os(Android) || os(FreeBSD) || canImport(Darwin)

#if os(Linux) || os(Android)
import CPlatformExecutors

private let sys_pthread_getname_np = CPlatformExecutors_pthread_getname_np
private let sys_pthread_setname_np = CPlatformExecutors_pthread_setname_np
#if os(Android)
private typealias ThreadDestructor = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer
#else
private typealias ThreadDestructor = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
#endif
#elseif canImport(Darwin)
import Darwin

private let sys_pthread_getname_np = pthread_getname_np
// Emulate the same method signature as pthread_setname_np on Linux.
private func sys_pthread_setname_np(
  _ p: pthread_t,
  _ pointer: UnsafePointer<Int8>
) -> Int32 {
  assert(pthread_equal(pthread_self(), p) != 0)
  pthread_setname_np(pointer)
  // Will never fail on macOS so just return 0 which will be used on linux to signal it not failed.
  return 0
}
private typealias ThreadDestructor = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?

#endif

private func sysPthread_create(
  handle: UnsafeMutablePointer<pthread_t?>,
  destructor: @escaping ThreadDestructor,
  args: UnsafeMutableRawPointer?
) -> CInt {
  #if canImport(Darwin)
  return pthread_create(handle, nil, destructor, args)
  #else
  #if canImport(Musl)
  var handleLinux: OpaquePointer? = nil
  let result = pthread_create(
    &handleLinux,
    nil,
    destructor,
    args
  )
  #else
  var handleLinux = pthread_t()
  let result = pthread_create(
    &handleLinux,
    nil,
    destructor,
    args
  )
  #endif
  handle.pointee = handleLinux
  return result
  #endif
}

enum PThread {
  typealias ThreadHandle = pthread_t
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
      guard sys_pthread_getname_np(thread, ptr.baseAddress!, ptr.count) == 0 else {
        return nil
      }

      let buffer: UnsafeRawBufferPointer =
        UnsafeRawBufferPointer(UnsafeBufferPointer<CChar>(rebasing: ptr.prefix { $0 != 0 }))
      return String(decoding: buffer, as: Unicode.UTF8.self)
    }
  }

  static func run(
    handle: inout PThread.ThreadHandle?,
    args: Box<Thread.ThreadBoxValue>
  ) {
    let argv0 = Unmanaged.passRetained(args).toOpaque()
    let res = sysPthread_create(
      handle: &handle,
      destructor: {
        // Cast to UnsafeMutableRawPointer? and force unwrap to make the
        // same code work on macOS and Linux.
        let boxed = Unmanaged<Thread.ThreadBox>
          .fromOpaque(($0 as UnsafeMutableRawPointer?)!)
          .takeRetainedValue()
        let (body, name) = (boxed.value.body, boxed.value.name)
        let hThread: PThread.ThreadHandle = pthread_self()

        if let name = name {
          let maximumThreadNameLength: Int
          #if os(Linux) || os(Android)
          maximumThreadNameLength = 15
          #else
          maximumThreadNameLength = .max
          #endif
          name.prefix(maximumThreadNameLength).withCString { namePtr in
            // this is non-critical so we ignore the result here, we've seen
            // EPERM in containers.
            _ = sys_pthread_setname_np(hThread, namePtr)
          }
        }

        body()

        #if os(Android)
        return UnsafeMutableRawPointer(bitPattern: 0xdeadbee)!
        #else
        return nil
        #endif
      },
      args: argv0
    )
    precondition(res == 0, "Unable to create thread: \(res)")
  }

  static func isCurrentThread(_ thread: PThread.ThreadHandle) -> Bool {
    return pthread_equal(thread, pthread_self()) != 0
  }

  static var currentThread: PThread.ThreadHandle {
    return pthread_self()
  }

  static func compareThreads(_ lhs: PThread.ThreadHandle, _ rhs: PThread.ThreadHandle) -> Bool {
    return pthread_equal(lhs, rhs) != 0
  }

  static func joinThread(_ thread: PThread.ThreadHandle) {
    let result = pthread_join(thread, nil)
    precondition(result == 0, "pthread_join failed with error code: \(result)")
  }
}

#endif
