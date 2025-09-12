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

#if os(Windows) || BUILDING_DOCS

#if canImport(WinSDK)
import WinSDK
#elseif BUILDING_DOCS
// We define some types here for cases where we don't have the Windows SDK
// (this is really to make documentation possible, as MSG is used in the
// public interface).

/// An opaque structure representing a window.
@_documentation(visibility: internal)
public struct _HWND { private var _reserved: Int }

/// A window handle identifies a window.
@_documentation(visibility: internal)
public typealias HWND = UnsafeMutablePointer<_HWND>

/// A unsigned 32-bit integer.
@_documentation(visibility: internal)
public typealias UINT = UInt32

/// An unsigned integer of pointer size.
@_documentation(visibility: internal)
public typealias UINT_PTR = UInt

/// An unsigned 32-bit integer.
@_documentation(visibility: internal)
public typealias DWORD = UInt32

/// A 32-bit integer.
@_documentation(visibility: internal)
public typealias LONG = Int32

/// A signed integer of pointer size.
@_documentation(visibility: internal)
public typealias LONG_PTR = Int

/// The type of the wParam message argument.
@_documentation(visibility: internal)
public typealias WPARAM = UINT_PTR

/// The type of the lParam message argument.
@_documentation(visibility: internal)
public typealias LPARAM = LONG_PTR

/// (Windows) Represents a particular point on the screen.
///
/// See [POINT structure (windef.h)](https://learn.microsoft.com/en-us/windows/win32/api/windef/ns-windef-point).
@_documentation(visibility: internal)
public struct POINT {
  /// The x-coordinate of this `POINT`.
  public var x: LONG
  /// The y-coordinate of this `POINT`.
  public var y: LONG
}

/// (Windows) A Win32 message, as retrieved by [GetMessage](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getmessage) et al.
///
/// See [MSG structure (winuser.h)](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-msg).
public struct MSG {
  /// The window this message is being sent to
  public var hwnd: HWND
  /// The numeric ID for the message (e.g. WM_LBUTTONDOWN)
  public var message: UINT
  /// A message-specific parameter
  public var wParam: WPARAM
  /// A message-specitic parameter
  public var lParam: LPARAM
  /// The system tick count at which the message was posted.
  public var time: DWORD
  /// The location of the mouse pointer, in screen coordinates, when the
  /// message was posted.
  public var pt: POINT
}

/// An opaque structure representing a thread pool.
@_documentation(visibility: internal)
public struct _TP_POOL { private var _reserved: Int }

/// (Windows) A pointer to an opaque structure representing a thread pool.
///
/// See [Thread Pools](https://learn.microsoft.com/en-us/windows/win32/procthread/thread-pools).
public typealias PTP_POOL = UnsafeMutablePointer<_TP_POOL>
#endif  // !canImport(WinSDK)

#if canImport(WinSDK)
internal import Synchronization

@available(macOS 14.0, *)
extension ExecutorJob {

  fileprivate var win32ThreadPoolExecutor: UnownedTaskExecutor {
    get {
      return unsafe withUnsafeExecutorPrivateData {
        unsafe $0.withMemoryRebound(to: UnownedTaskExecutor.self) {
          return unsafe $0[0]
        }
      }
    }
    set {
      unsafe withUnsafeExecutorPrivateData {
        unsafe $0.withMemoryRebound(to: UnownedTaskExecutor.self) {
          unsafe $0[0] = newValue
        }
      }
    }
  }

  // The code below deals with the fact that the Timestamp may not fit
  // into the private storage.  If it doesn't, we need to allocate it
  // somewhere and store a pointer instead.

  fileprivate var win32TimestampIsIndirect: Bool {
    return unsafe MemoryLayout<OpaquePointer>.stride * 2
      < MemoryLayout<Win32EventLoopExecutor.Timestamp>.size
  }

  fileprivate var win32TimestampPointer: UnsafeMutablePointer<Win32EventLoopExecutor.Timestamp> {
    get {
      assert(win32TimestampIsIndirect)
      return unsafe withUnsafeExecutorPrivateData {
        unsafe $0.withMemoryRebound(to: UnsafeMutablePointer<Win32EventLoopExecutor.Timestamp>.self) {
          return unsafe $0[0]
        }
      }
    }
    set {
      assert(win32TimestampIsIndirect)
      unsafe withUnsafeExecutorPrivateData {
        unsafe $0.withMemoryRebound(to: UnsafeMutablePointer<Win32EventLoopExecutor.Timestamp>.self) {
          unsafe $0[0] = newValue
        }
      }
    }
  }

  fileprivate var win32Timestamp: Win32EventLoopExecutor.Timestamp {
    get {
      guard win32TimestampIsIndirect else {
        return unsafe withUnsafeExecutorPrivateData {
          return unsafe $0.assumingMemoryBound(
            to: Win32EventLoopExecutor.Timestamp.self
          )[0]
        }
      }
      let ptr = unsafe win32TimestampPointer
      return unsafe ptr.pointee
    }
    set {
      if win32TimestampIsIndirect {
        let ptr = unsafe win32TimestampPointer
        unsafe ptr.pointee = newValue
      } else {
        unsafe withUnsafeExecutorPrivateData {
          unsafe $0.withMemoryRebound(to: Win32EventLoopExecutor.Timestamp.self) {
            unsafe $0[0] = newValue
          }
        }
      }
    }
  }

  fileprivate var win32Sequence: UInt {
    get {
      return unsafe withUnsafeExecutorPrivateData {
        return unsafe $0.assumingMemoryBound(to: UInt.self)[0]
      }
    }
    set {
      return unsafe withUnsafeExecutorPrivateData {
        unsafe $0.withMemoryRebound(to: UInt.self) {
          unsafe $0[0] = newValue
        }
      }
    }
  }

  fileprivate mutating func setupWin32Timestamp() {
    // If a Timestamp won't fit, allocate
    if win32TimestampIsIndirect {
      let ptr: UnsafeMutablePointer<Win32EventLoopExecutor.Timestamp>
      // Try to use the task allocator if it has one
      if let allocator {
        unsafe ptr = allocator.allocate(as: Win32EventLoopExecutor.Timestamp.self)
      } else {
        unsafe ptr = .allocate(capacity: 1)
      }
      unsafe self.win32TimestampPointer = ptr
    }
  }

  fileprivate mutating func clearWin32Timestamp() {
    // If we allocated the Timestamp, deallocate
    if win32TimestampIsIndirect {
      let ptr = unsafe self.win32TimestampPointer
      if let allocator {
        unsafe allocator.deallocate(ptr)
      } else {
        unsafe ptr.deallocate()
      }
    }
  }
}
#endif  // !canImport(WinSDK)

/// The Win32EventLoopExecutor delegate protocol.
///
/// The delegate protocol allows programs to inject their own code into the
/// event loop, for instance to process messages for non-modal dialogs.
public protocol Win32EventLoopExecutorDelegate {

  /// Called before the event loop calls TranslateMessage()
  ///
  /// - Parameters:
  ///
  ///   - message:  The message being processed.
  ///
  /// - Returns: `true` to prevent the event loop from processing the message
  /// further, for instance if the `preTranslateMessage` function has
  /// completely handled the message somehow.
  func preTranslateMessage(_ message: inout MSG) -> Bool

}

#if canImport(WinSDK)
/// Retrieve a message from the Win32 message queue
///
/// This exists to work around the incorrect return type declared by the
/// GetMessage() API, which claims to return BOOL, but really returns an
/// INT (0, 1, or -1).
private func GetMessage(
  _ message: inout MSG,
  _ hWnd: HWND?,
  _ wMsgFilterMin: UINT,
  _ wMsgFilterMax: UINT
) -> Int {
  let getMessagePtr = unsafe GetMessageW
  let getMessage = unsafe unsafeBitCast(
    getMessagePtr,
    to: ((LPMSG?, HWND?, UINT, UINT) -> Int8).self
  )
  return Int(unsafe getMessage(&message, hWnd, wMsgFilterMin, wMsgFilterMax))
}
#endif  // canImport(WinSDK)

/// An executor that uses a Windows event loop.
///
/// This executor will stop on receipt of a `WM_QUIT` message, and can
/// be used as a nested event loop as well (i.e. you can call ``run()`` from
/// within a task or from a message handler).
///
/// The message loop runs in an alertable wait state, so will cause any
/// Windows APCs to execute.  It also allows you to intercept messages by
/// providing a delegate, for instance to allow processing of non-modal
/// dialogs or accelerator tables.
///
/// ## Usage
///
/// ```swift
/// // Create main executor on current thread
/// let mainExecutor = Win32EventLoopExecutor()
///
/// // Run the executor loop
/// try mainExecutor.run()
///
/// // Stop the executor from another context
/// mainExecutor.stop()
/// ```
@safe
@available(macOS 9999, *)
public final class Win32EventLoopExecutor: SerialExecutor, RunLoopExecutor, @unchecked Sendable {

  struct Timestamp {
    /// The earliest time at which a job should run.
    ///
    /// Jobs will never be run earlier than this.
    var target: UInt64

    /// The maximum (ideal) tolerable delay.
    ///
    /// We make no guarantee that we won't run over this, but it is taken
    /// into consideration when scheduling jobs.
    var leeway: UInt64

    /// The latest time at which a job should (ideally) run.
    ///
    /// We may run the job after this point, but we will not run other jobs
    /// with later deadlines before this job.
    var deadline: UInt64 {
      get {
        if UInt64.max - target < leeway {
          return UInt64.max
        }
        return target + leeway
      }
      set {
        if newValue < leeway {
          target = 0
        } else {
          target = newValue - leeway
        }
      }
    }
  }

  private enum WaitQueue: Int {
    case continuous = 0
    case suspending = 1
  }

  #if canImport(WinSDK)
  private let waitQueues: Mutex<[PriorityQueue<UnownedJob>]>
  private let runQueue: Mutex<PriorityQueue<UnownedJob>>
  private var currentRunQueue: PriorityQueue<UnownedJob>

  private var dwThreadId: DWORD?
  private var hEvent: HANDLE!
  private let bShouldStop: Atomic<Bool>
  private let sequence: Atomic<UInt>
  #endif  // canImport(WinSDK)

  private(set) public var isMainExecutor: Bool

  /// The delegate allows users of ``Win32EventLoopExecutor`` to inject
  /// their own code into the event loop, for instance to process messages
  /// for non-modal dialogs.
  public var delegate: (any Win32EventLoopExecutorDelegate)?

  /// Construct a Win32EventLoopExecutor
  ///
  /// - Parameters:
  ///
  ///   - isMainExecutor: set this to `true` if this is the main executor,
  ///                     and `false` otherwise.
  ///
  public init(isMainExecutor: Bool = false) {
    self.isMainExecutor = isMainExecutor

    #if canImport(WinSDK)
    self.dwThreadId = nil
    self.bShouldStop = Atomic<Bool>(false)
    self.sequence = Atomic<UInt>(0)
    guard let hEvent = CreateEventW(nil, true, false, nil) else {
      let dwError = GetLastError()
      fatalError("Unable to create event: \(String(dwError, radix: 16))")
    }
    unsafe self.hEvent = hEvent

    self.runQueue = Mutex(PriorityQueue(compare: compareJobsByPriority))
    self.currentRunQueue = PriorityQueue(compare: compareJobsByPriority)

    let compareTimestamps = { (lhs: UnownedJob, rhs: UnownedJob) -> Bool in
      return ExecutorJob(lhs).win32Timestamp.deadline
        < ExecutorJob(rhs).win32Timestamp.deadline
    }

    self.waitQueues = Mutex(
      [
        PriorityQueue(compare: compareTimestamps),
        PriorityQueue(compare: compareTimestamps),
      ]
    )
    #endif
  }

  deinit {
    #if canImport(WinSDK)
    unsafe CloseHandle(hEvent)
    #endif
  }

  #if canImport(WinSDK)
  private func wakeEventLoop() {
    let bRet = unsafe SetEvent(hEvent)
    if !bRet {
      let dwError = GetLastError()
      fatalError("SetEvent() failed while trying to wake event loop: error 0x\(String(dwError, radix: 16))")
    }
  }
  #endif  // canImport(WinSDK)

  public func isIsolatingCurrentContext() -> Bool {
    #if canImport(WinSDK)
    let dwCurrentThreadId = GetCurrentThreadId()
    return dwThreadId == dwCurrentThreadId
    #else
    return false
    #endif
  }

  public func run() throws {
    #if canImport(WinSDK)

    // Make sure we're running on the same thread every time
    let dwCurrentThreadId = GetCurrentThreadId()
    if dwThreadId == nil {
      dwThreadId = dwCurrentThreadId
    }

    precondition(
      dwThreadId == dwCurrentThreadId,
      "Win32EventLoopExecutor must always run on the same thread"
    )

    while true {
      // Switch queues
      runQueue.withLock {
        swap(&$0, &currentRunQueue)
        unsafe ResetEvent(hEvent)
      }

      // Move jobs from the timer queue to the run queue as needed
      fireTimerQueues()

      // Run anything in the run queue at this point
      while let job = currentRunQueue.pop() {
        unsafe ExecutorJob(job).runSynchronously(
          on: self.asUnownedSerialExecutor()
        )
      }

      // Work out how long to wait for
      let dwMsToWait = computeNextTimerWait()

      // Wait for messages, the stop event, or APCs
      let dwRet = unsafe MsgWaitForMultipleObjectsEx(
        1,
        &hEvent,
        dwMsToWait,
        DWORD(QS_ALLINPUT),
        DWORD(MWMO_ALERTABLE)
      )

      // The event is signalled when one of the following is true:
      //
      // * A new job was queued for excecution.
      // * A new job was scheduled for later excecution.
      // * The stop() method has been called.
      //
      if dwRet == WAIT_OBJECT_0 {
        if bShouldStop.load(ordering: .acquiring) {
          bShouldStop.store(false, ordering: .relaxed)
          break
        }
      }

      // If we have a message waiting, process it
      if dwRet == WAIT_OBJECT_0 + 1 {
        var msg = unsafe MSG()

        while unsafe PeekMessageW(&msg, nil, 0, 0, UINT(PM_REMOVE)) {
          if msg.message == WM_QUIT {
            // We received WM_QUIT, so exit; note that we re-post the quit
            // message, in case we're nested somehow.  It doesn't matter too
            // much if this is the outermost loop - we'll just quit at that
            // point.
            PostQuitMessage(CInt(unsafe msg.wParam))
            return
          }

          var skipMessageProcessing = false
          if let delegate {
            skipMessageProcessing = unsafe delegate.preTranslateMessage(&msg)
          }

          if !skipMessageProcessing {
            unsafe TranslateMessage(&msg)
            unsafe DispatchMessageW(&msg)
          }
        }
      }

    }

    #endif  // canImport(WinSDK)
  }

  public func stop() {
    #if canImport(WinSDK)
    bShouldStop.store(true, ordering: .releasing)
    wakeEventLoop()
    #endif
  }

  public func enqueue(_ job: consuming ExecutorJob) {
    #if canImport(WinSDK)
    // Tag it with a sequence number to force ordering for same-priority jobs
    let (newSequence, _) = sequence.wrappingAdd(1, ordering: .relaxed)
    job.win32Sequence = newSequence

    let unownedJob = UnownedJob(job)
    runQueue.withLock {
      $0.push(unownedJob)
    }

    wakeEventLoop()
    #endif
  }

  #if canImport(WinSDK)
  /// Process the timer queues.
  ///
  /// We maintain two timer queues, one for continuous time, and one
  /// for suspending time.  The difference is that one of them is
  /// driven by `QueryInterruptTimePrecise()`, while the other is driven
  /// by `QueryUnbiasedInterruptTimePrecise()`.
  ///
  /// This function will move jobs whose timers have elapsed to the run
  /// queue.
  func fireTimerQueues() {
    var now: [UInt64] = [0, 0]

    unsafe QueryInterruptTimePrecise(&now[WaitQueue.continuous.rawValue])
    unsafe QueryUnbiasedInterruptTimePrecise(&now[WaitQueue.suspending.rawValue])

    waitQueues.withLock { queues in
      for queue in WaitQueue.continuous.rawValue...WaitQueue.suspending.rawValue {
        // Run all of the queued events
        while let job = queues[queue].pop(
          when: {
            ExecutorJob($0).win32Timestamp.target <= now[queue]
          }
        ) {
          var theJob = ExecutorJob(job)
          theJob.clearWin32Timestamp()
          currentRunQueue.push(job)
        }
      }
    }
  }

  /// Work out how long we should wait for on the next loop.
  ///
  /// Looking at the timer queues, work out how long we want to wait for
  /// events on the next pass around the loop.
  ///
  /// - Returns: the number of milliseconds to tell Windows to wait.
  func computeNextTimerWait() -> DWORD {
    var now: [UInt64] = [0, 0]

    unsafe QueryInterruptTimePrecise(&now[WaitQueue.continuous.rawValue])
    unsafe QueryUnbiasedInterruptTimePrecise(&now[WaitQueue.suspending.rawValue])

    // Find the smallest time we need to wait
    var lowestDelta: UInt64?
    var leeway: UInt64?

    waitQueues.withLock { queues in
      for queue in WaitQueue.continuous.rawValue...WaitQueue.suspending.rawValue {
        if let job = queues[queue].top {
          let timestamp = ExecutorJob(job).win32Timestamp
          let delta = timestamp.deadline - now[queue]

          if lowestDelta == nil {
            lowestDelta = delta
            leeway = timestamp.leeway
          } else if delta < lowestDelta! {
            lowestDelta = delta
            leeway = timestamp.leeway
          }
        }
      }
    }

    // If there's nothing to wait for, return INFINITE
    guard let lowestDelta, let leeway else {
      return INFINITE
    }

    // Compute the desired fire time
    let fireTime = lowestDelta - leeway

    // Convert to milliseconds
    var msToWait = fireTime / 10000

    // If we have less than 15ms of leeway, reduce `msToWait` so that
    // we spin up to the fire time.
    //
    // The reason for this is that Windows waits in an unusual way; it actually
    // keeps track of time in 15.625ms (1/64s) "ticks", and if you ask to wait
    // for less than one tick it will run an inaccurate delay loop.  Further,
    // because of when it decrements the tick count, it may actually return by
    // up to one tick *early*, depending on when in a tick you ask to wait.
    if leeway < 156250 {
      msToWait -= min(msToWait, 15)
    }

    // INFINITE is 0xffffffff (see <WinBase.h>)
    if msToWait >= INFINITE {
      msToWait = UInt64(INFINITE - 1)
    }

    return DWORD(truncatingIfNeeded: msToWait)
  }
  #endif  // canImport(WinSDK)

  /// Return `self` as a `SchedulingExecutor`.
  public var asSchedulable: SchedulingExecutor? {
    return self
  }
}

@available(macOS 9999, *)
extension Win32EventLoopExecutor: SchedulingExecutor {

  public func enqueue<C: Clock>(
    _ job: consuming ExecutorJob,
    after delay: C.Duration,
    tolerance: C.Duration? = nil,
    clock: C
  ) {
    #if canImport(WinSDK)
    let queue: WaitQueue
    if let _ = clock as? ContinuousClock {
      queue = .continuous
    } else if let _ = clock as? SuspendingClock {
      queue = .suspending
    } else {
      clock.enqueue(
        job,
        on: self,
        at: clock.now.advanced(by: delay),
        tolerance: tolerance
      )
      return
    }

    var now: UInt64 = 0
    switch queue {
    case .continuous:
      unsafe QueryUnbiasedInterruptTimePrecise(&now)
    case .suspending:
      unsafe QueryInterruptTimePrecise(&now)
    }

    let delayAsDuration = delay as! Duration
    let (delaySecs, delayAttos) = delayAsDuration.components
    let delay100ns = max(delaySecs * 10_000_000 + delayAttos / 100_000_000_000, 0)
    let tolerance100ns: Int64
    if let tolerance {
      let toleranceAsDuration = tolerance as! Duration
      let (toleranceSecs, toleranceAttos) = toleranceAsDuration.components
      tolerance100ns = max(
        toleranceSecs * 10_000_000
          + toleranceAttos / 100_000_000_000,
        0
      )
    } else {
      // Default tolerance is 10%, with a maximum of 100ms and a minimum of
      // 15.625ms (so as not to needlessly trigger spinning for accuracy).
      tolerance100ns = max(min(delay100ns / 10, 1_000_000), 156250)
    }

    let timestamp = Timestamp(
      target: now + UInt64(delay100ns),
      leeway: UInt64(tolerance100ns)
    )

    job.setupWin32Timestamp()
    job.win32Timestamp = timestamp

    let unownedJob = UnownedJob(job)
    waitQueues.withLock { queues in
      queues[queue.rawValue].push(unownedJob)
    }
    wakeEventLoop()
    #endif  // canImport(WinSDK)
  }

}

@available(macOS 9999, *)
extension Win32EventLoopExecutor: MainExecutor {}

/// An executor that uses a Win32 thread pool.
///
/// `Win32ThreadPoolExecutor` is a `TaskExecutor` that schedules tasks using
/// the [Win32 Thread Pool API](https://learn.microsoft.com/en-us/windows/win32/procthread/thread-pooling).
///
/// ## Usage
///
/// ```swift
/// // Create pool for parallel processing
/// let pool = Win32ThreadPoolExecutor(poolSize: 4)
///
/// await withTaskExecutorPreference(pool) {
///     // Jobs distributed across the pool
///     async let result1 = heavyComputation1()
///     async let result2 = heavyComputation2()
///     async let result3 = heavyComputation3()
///
///     return await [result1, result2, result3]
/// }
/// ```
@safe
@available(macOS 9999, *)
public final class Win32ThreadPoolExecutor: TaskExecutor, @unchecked Sendable {

  #if canImport(WinSDK)
  private var cbeHighPriority = unsafe TP_CALLBACK_ENVIRON()
  private var cbeLowPriority = unsafe TP_CALLBACK_ENVIRON()
  private var cbeNormalPriority = unsafe TP_CALLBACK_ENVIRON()
  #endif

  /// Construct a Win32ThreadPoolExecutor.
  ///
  /// This is a convenience initializer to avoid having to write unsafe
  /// in the normal case where you want to use the default thread pool.
  /// Note that the default thread pool presently has a size of 500 threads,
  /// so for CPU-bound programs, you may wish to create a more appropriately
  /// sized pool.
  public convenience init() {
    self.init(pool: nil)
  }

  /// Construct a Win32ThreadPoolExecutor.
  ///
  /// This is a convenience intializer that creates a thread pool with a
  /// specified maximum size.
  ///
  /// - Parameters:
  ///
  ///   - poolSize: The maximum number of threads in the pool.  Must
  ///               be greater than 0.
  ///
  public convenience init(poolSize: Int) {
    #if canImport(WinSDK)
    let pool = CreateThreadpool(nil)
    SetThreadpoolThreadMaximum(pool, DWORD(poolSize))
    self.init(pool: pool)
    #else
    self.init(pool: nil)
    #endif
  }

  /// Construct a Win32ThreadPoolExecutor.
  ///
  /// - Parameters:
  ///
  ///   - pool:  The thread pool to use; `nil` means use the default thread
  ///            pool.
  ///
  public init(pool: PTP_POOL?) {
    #if canImport(WinSDK)
    unsafe InitializeThreadpoolEnvironment(&cbeHighPriority)
    unsafe InitializeThreadpoolEnvironment(&cbeLowPriority)
    unsafe InitializeThreadpoolEnvironment(&cbeNormalPriority)

    unsafe SetThreadpoolCallbackPriority(
      &cbeHighPriority,
      TP_CALLBACK_PRIORITY_HIGH
    )
    unsafe SetThreadpoolCallbackPriority(
      &cbeLowPriority,
      TP_CALLBACK_PRIORITY_LOW
    )
    unsafe SetThreadpoolCallbackPriority(
      &cbeNormalPriority,
      TP_CALLBACK_PRIORITY_NORMAL
    )

    if let pool = unsafe pool {
      unsafe SetThreadpoolCallbackPool(&cbeHighPriority, pool)
      unsafe SetThreadpoolCallbackPool(&cbeLowPriority, pool)
      unsafe SetThreadpoolCallbackPool(&cbeNormalPriority, pool)
    }
    #endif  // canImport(WinSDK)
  }

  deinit {
    #if canImport(WinSDK)
    unsafe DestroyThreadpoolEnvironment(&cbeHighPriority)
    unsafe DestroyThreadpoolEnvironment(&cbeLowPriority)
    unsafe DestroyThreadpoolEnvironment(&cbeNormalPriority)
    #endif
  }

  #if canImport(WinSDK)
  private func withEnvironment<R>(
    for priority: JobPriority,
    body: (UnsafeMutablePointer<TP_CALLBACK_ENVIRON>) -> R
  ) -> R {
    if priority.rawValue <= TaskPriority.low.rawValue {
      return unsafe withUnsafeMutablePointer(to: &cbeLowPriority, body)
    } else if priority.rawValue >= TaskPriority.high.rawValue {
      return unsafe withUnsafeMutablePointer(to: &cbeHighPriority, body)
    } else {
      return unsafe withUnsafeMutablePointer(to: &cbeNormalPriority, body)
    }
  }
  #endif  // canImport(WinSDK)

  public func enqueue(_ job: consuming ExecutorJob) {
    #if canImport(WinSDK)
    unsafe job.win32ThreadPoolExecutor = self.asUnownedTaskExecutor()

    let priority = job.priority
    let unownedJob = UnownedJob(job)
    let work = unsafe withEnvironment(for: priority) { environment in
      unsafe CreateThreadpoolWork(
        _runJobOnThreadPool,
        unsafe unsafeBitCast(
          unownedJob,
          to: PVOID.self
        ),
        environment
      )
    }

    unsafe SubmitThreadpoolWork(work)
    unsafe CloseThreadpoolWork(work)
    #endif
  }

  /// Return `self` as a `SchedulingExecutor`.
  public var asSchedulable: SchedulingExecutor? {
    return self
  }
}

#if canImport(WinSDK)
@_cdecl("_swift_runJobOnThreadPool")
private func _runJobOnThreadPool(
  instance: PTP_CALLBACK_INSTANCE?,
  context: UnsafeMutableRawPointer?,
  work: PTP_WORK?
) {
  let job = unsafe unsafeBitCast(context, to: UnownedJob.self)
  let executor = unsafe ExecutorJob(job).win32ThreadPoolExecutor
  unsafe job.runSynchronously(on: executor)
}

@_cdecl("_swift_runJobFromTimerCallback")
private func _runJobFromTimerCallback(
  instance: PTP_CALLBACK_INSTANCE?,
  context: UnsafeMutableRawPointer?,
  timer: PTP_TIMER?
) {
  let job = unsafe unsafeBitCast(context, to: UnownedJob.self)
  let executor = unsafe ExecutorJob(job).win32ThreadPoolExecutor
  unsafe job.runSynchronously(on: executor)
  unsafe CloseThreadpoolTimer(timer)
}
#endif  // canImport(WinSDK)

@available(macOS 9999, *)
extension Win32ThreadPoolExecutor: SchedulingExecutor {

  public func enqueue<C: Clock>(
    _ job: consuming ExecutorJob,
    after delay: C.Duration,
    tolerance: C.Duration? = nil,
    clock: C
  ) {
    #if canImport(WinSDK)
    var fireTime: FILETIME

    // The thread pool timers can either do a suspending delay (that is, the
    // time spent asleep does not count), *or* an absolute time, so to do
    // a delay from a continuous clock, we calculate the expected fire time
    // from the delay and the current time.
    let delay100ns: Int64
    if let _ = clock as? ContinuousClock {
      let continuousDuration = delay as! Duration
      let (delaySecs, delayAttos) = continuousDuration.components
      delay100ns = max(delaySecs * 10_000_000 + delayAttos / 100_000_000_000, 0)

      var now = FILETIME(dwLowDateTime: 0, dwHighDateTime: 0)
      unsafe GetSystemTimePreciseAsFileTime(&now)

      let now100ns = UInt64(now.dwLowDateTime) | UInt64(now.dwHighDateTime) << 32
      let target100ns = now100ns + UInt64(delay100ns)

      fireTime = FILETIME(
        dwLowDateTime:
          DWORD(truncatingIfNeeded: target100ns),
        dwHighDateTime:
          DWORD(truncatingIfNeeded: target100ns >> 32)
      )
    } else if let _ = clock as? SuspendingClock {
      let suspendingDuration = delay as! Duration
      let (delaySecs, delayAttos) = suspendingDuration.components
      delay100ns = max(delaySecs * 10_000_000 + delayAttos / 100_000_000_000, 0)

      fireTime = FILETIME(
        dwLowDateTime:
          DWORD(truncatingIfNeeded: -delay100ns),
        dwHighDateTime:
          DWORD(truncatingIfNeeded: -delay100ns >> 32)
      )
    } else {
      clock.enqueue(
        job,
        on: self,
        at: clock.now.advanced(by: delay),
        tolerance: tolerance
      )
      return
    }

    unsafe job.win32ThreadPoolExecutor = self.asUnownedTaskExecutor()

    let priority = job.priority
    let unownedJob = UnownedJob(job)
    let timer = unsafe withEnvironment(for: priority) { environment in
      unsafe CreateThreadpoolTimer(
        _runJobFromTimerCallback,
        unsafe unsafeBitCast(
          unownedJob,
          to: UnsafeMutableRawPointer.self
        ),
        environment
      )
    }

    guard let timer = unsafe timer else {
      let dwError = GetLastError()
      fatalError("unable to create Win32 thread pool timer: error 0x\(String(dwError, radix: 16))")
    }

    let msWindowLength: DWORD
    if let tolerance {
      let toleranceAsDuration: Duration
      if let _ = clock as? ContinuousClock {
        toleranceAsDuration = tolerance as! Duration
      } else if let _ = clock as? SuspendingClock {
        toleranceAsDuration = tolerance as! Duration
      } else {
        fatalError("Unknown clock - we shouldn't get here")
      }
      let (toleranceSecs, toleranceAttos) = toleranceAsDuration.components
      msWindowLength =
        DWORD(toleranceSecs * 1000)
        + DWORD(toleranceAttos / 1_000_000_000_000_000)
      //                                 ^ns     ^us ^ms
    } else {
      // Default tolerance is 10%, with a maximum of 100ms and a minimum of
      // 15ms, same as for the event loop.
      msWindowLength = max(min(DWORD(delay100ns / 100000), 100), 15)
    }

    unsafe SetThreadpoolTimer(timer, &fireTime, 0, msWindowLength)
    #endif  // canImport(WinSDK)
  }

}

#if canImport(WinSDK)
@available(macOS 14.0, *)
private func compareJobsByPriority(
  lhs: UnownedJob,
  rhs: UnownedJob
) -> Bool {
  if lhs.priority == rhs.priority {
    // If they're the same priority, compare the sequence numbers to
    // ensure this queue gives stable ordering.  We want the lowest
    // sequence number first, but note that we want to handle wrapping.
    let delta = ExecutorJob(lhs).win32Sequence &- ExecutorJob(rhs).win32Sequence
    return (delta >> (UInt.bitWidth - 1)) != 0
  }
  return lhs.priority > rhs.priority
}
#endif

#endif  // os(Windows) || BUILDING_DOCS
