##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift.org open source project
##
## Copyright (c) 2026 Apple Inc. and the Swift project authors
## Licensed under Apache License v2.0 with Runtime Library Exception
##
## See https://swift.org/LICENSE.txt for license information
## See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
##
##===----------------------------------------------------------------------===##

add_library(PlatformExecutors
  Dispatch/DispatchGlobalExecutor.swift
  Dispatch/DispatchMainExecutor.swift
  Dispatch/DispatchSerialExecutor.swift
  Dispatch/DispatchTaskExecutor.swift
  Dispatch/Internal/DispatchRuntimeMethods.swift
  IO/HighLevel/File.swift
  IO/HighLevel/FilePermissions.swift
  IO/HighLevel/TCPConnection.swift
  IO/HighLevel/TCPListener.swift
  IO/HighLevel/withOperationScheduler.swift
  IO/LowLevel/FileOperationScheduler.swift
  IO/LowLevel/IOError.swift
  IO/LowLevel/IPv4Address.swift
  IO/LowLevel/IPv6Address.swift
  IO/LowLevel/OperationScheduler.swift
  IO/LowLevel/SocketAddress.swift
  IO/LowLevel/SocketShutdownDirection.swift
  IO/LowLevel/TCPSocketOperationScheduler.swift
  Internal/AsyncTemporaryAllocation.swift
  Internal/ExecutorJob+Sequence.swift
  Internal/JobQueue.swift
  Internal/PriorityQueue.swift
  Internal/TemporaryAllocation.swift
  Internal/UnownedJob+Compare.swift
  PThread/Internal/AsyncDo.swift
  PThread/Internal/BlockingWorkQueue.swift
  PThread/Internal/Box.swift
  PThread/Internal/ConditionLock.swift
  PThread/Internal/IO/ConditionSelectorBackend.swift
  PThread/Internal/IO/EpollReadinessBackend.swift
  PThread/Internal/IO/EventFileDescriptor.swift
  PThread/Internal/IO/FileSyscall.swift
  PThread/Internal/IO/IOBackend.swift
  PThread/Internal/IO/IOError+SyscallError.swift
  PThread/Internal/IO/IOOperation.swift
  PThread/Internal/IO/IOUringBackend.swift
  PThread/Internal/IO/IOWaitStrategy.swift
  PThread/Internal/IO/KQueueReadinessBackend.swift
  PThread/Internal/IO/PThreadExecutor+FileOperations.swift
  PThread/Internal/IO/PThreadExecutor+TCPSocketOperations.swift
  PThread/Internal/IO/PThreadTaskExecutor+FileOperations.swift
  PThread/Internal/IO/PThreadTaskExecutor+TCPSocketOperations.swift
  PThread/Internal/IO/PlatformIOBackend.swift
  PThread/Internal/IO/ReadinessEvent.swift
  PThread/Internal/IO/ReadinessOperations.swift
  PThread/Internal/IO/SocketAddress+POSIX.swift
  PThread/Internal/IO/StreamSocketSyscall.swift
  PThread/Internal/IO/TimerFileDescriptor.swift
  PThread/Internal/IO/_IntegerBitPacking.swift
  PThread/Internal/IO/syscall.swift
  PThread/Internal/IO/timespec+duration.swift
  PThread/Internal/PThread.swift
  PThread/Internal/SystemCoreCount.swift
  PThread/Internal/Thread.swift
  PThread/PThreadExecutor.swift
  PThread/PThreadFile.swift
  PThread/PThreadIOBackend.swift
  PThread/PThreadMainExecutor.swift
  PThread/PThreadSerialExecutor.swift
  PThread/PThreadTCPConnection.swift
  PThread/PThreadTCPListener.swift
  PThread/PThreadTaskExecutor.swift
  PlatformExecutorFactory.swift
  PlatformSerialExecutor.swift
  PlatformTaskExecutor.swift
  Win32Executor/Win32NativeExecutors.swift)

target_link_libraries(PlatformExecutors PUBLIC
  CPlatformExecutors)
target_link_libraries(PlatformExecutors PRIVATE
  SwiftCollections::BasicContainers)
if(SwiftPlatformExecutors_ENABLE_EXPERIMENTAL_IO)
  target_link_libraries(PlatformExecutors PRIVATE
    SwiftCollections::DequeModule)
endif()
if(SwiftPlatformExecutors_ENABLE_EXPERIMENTAL_IO_URING)
  target_link_libraries(PlatformExecutors PRIVATE
    SwiftSystem::SystemPackage
    SwiftSystem::SystemSockets)
endif()

install(TARGETS PlatformExecutors
  EXPORT SwiftPlatformExecutorsTargets
  ARCHIVE DESTINATION "${${PROJECT_NAME}_INSTALL_LIBDIR}"
  LIBRARY DESTINATION "${${PROJECT_NAME}_INSTALL_LIBDIR}"
  RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")
emit_swift_interface(PlatformExecutors)
install_swift_interface(PlatformExecutors)
