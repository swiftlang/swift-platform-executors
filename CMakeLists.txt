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

cmake_minimum_required(VERSION 3.26...3.29)

set(CMAKE_C_VISIBILITY_PRESET "hidden")

project(SwiftPlatformExecutors
  LANGUAGES C Swift)

list(APPEND CMAKE_MODULE_PATH
  "${CMAKE_CURRENT_SOURCE_DIR}/cmake/modules")

if(NOT DEFINED BUILD_SHARED_LIBS)
  option(BUILD_SHARED_LIBS "Build shared libraries by default" YES)
endif()

option(${PROJECT_NAME}_INSTALL_NESTED_SUBDIR "Install libraries under a platform and architecture subdirectory" ON)
option(${PROJECT_NAME}_ENABLE_LIBRARY_EVOLUTION "Generate ABI resilient runtime libraries" NO)
option(${PROJECT_NAME}_ENABLE_PRESPECIALIZATION "Enable generic metadata prespecialization" NO)

# The SwiftPM traits of the package. The I/O interfaces require a toolchain that contains the split continuation of
# https://github.com/swiftlang/swift/pull/91981.
option(${PROJECT_NAME}_ENABLE_EXPERIMENTAL_IO "Build the experimental and highly unstable I/O interfaces (ExperimentalIO trait)" NO)
option(${PROJECT_NAME}_ENABLE_EXPERIMENTAL_IO_URING "Perform the I/O with io_uring on Linux (ExperimentalIOUring trait)" NO)

if(${PROJECT_NAME}_ENABLE_EXPERIMENTAL_IO_URING)
  if(NOT CMAKE_SYSTEM_NAME STREQUAL "Linux")
    message(FATAL_ERROR "${PROJECT_NAME}_ENABLE_EXPERIMENTAL_IO_URING is only supported on Linux")
  endif()
  # Like the trait, io_uring implies the I/O interfaces.
  set(${PROJECT_NAME}_ENABLE_EXPERIMENTAL_IO YES CACHE BOOL "" FORCE)
endif()

include(GNUInstallDirs)
include(PlatformInfo)
include(EmitSwiftInterface)
include(InstallSwiftInterface)
include(InstallExternalDependencies)

set(${PROJECT_NAME}_INSTALL_LIBDIR "${CMAKE_INSTALL_LIBDIR}/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>$<$<BOOL:${${PROJECT_NAME}_INSTALL_NESTED_SUBDIR}>:/${${PROJECT_NAME}_PLATFORM_SUBDIR}/${${PROJECT_NAME}_ARCH_SUBDIR}>")
set(${PROJECT_NAME}_INSTALL_SWIFTMODULEDIR "${CMAKE_INSTALL_LIBDIR}/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>$<$<BOOL:${${PROJECT_NAME}_INSTALL_NESTED_SUBDIR}>:/${${PROJECT_NAME}_PLATFORM_SUBDIR}>")

# Mirrors the Swift settings of Package.swift.
add_compile_options(
  "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-swift-version 6>"
  "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-package-name ${PROJECT_NAME}>"
  "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-enable-upcoming-feature ExistentialAny>"
  "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-enable-upcoming-feature MemberImportVisibility>"
  "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-enable-upcoming-feature InternalImportsByDefault>"
  "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-enable-upcoming-feature NonisolatedNonsendingByDefault>"
  "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-enable-experimental-feature Lifetimes>"
  "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-enable-experimental-feature BuiltinModule>"
  "$<$<COMPILE_LANGUAGE:Swift>:-strict-memory-safety>"
  "$<$<COMPILE_LANGUAGE:Swift>:-warnings-as-errors>"
  "$<$<AND:$<BOOL:${${PROJECT_NAME}_ENABLE_EXPERIMENTAL_IO}>,$<COMPILE_LANGUAGE:Swift>>:-DExperimentalIO>"
  # The split continuation is `anyAppleOS 9999` SPI in the toolchains that the I/O interfaces require.
  "$<$<AND:$<BOOL:${${PROJECT_NAME}_ENABLE_EXPERIMENTAL_IO}>,$<COMPILE_LANGUAGE:Swift>>:SHELL:-Xfrontend -disable-availability-checking>"
  "$<$<AND:$<BOOL:${${PROJECT_NAME}_ENABLE_EXPERIMENTAL_IO_URING}>,$<COMPILE_LANGUAGE:Swift>>:-DExperimentalIOUring>"
  "$<$<AND:$<BOOL:${${PROJECT_NAME}_ENABLE_LIBRARY_EVOLUTION}>,$<COMPILE_LANGUAGE:Swift>>:-enable-library-evolution>"
  "$<$<AND:$<BOOL:${${PROJECT_NAME}_ENABLE_PRESPECIALIZATION}>,$<COMPILE_LANGUAGE:Swift>>:SHELL:-Xfrontend -prespecialize-generic-metadata>")

# The availability macros of the Swift standard library, the same as Package.swift and swift-collections define them.
set(availability_defs
  "SwiftStdlib 5.0: macOS 10.14.4, iOS 12.2, watchOS 5.2, tvOS 12.2"
  "SwiftStdlib 5.1: macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0"
  "SwiftStdlib 5.6: macOS 12.3, iOS 15.4, watchOS 8.5, tvOS 15.4"
  "SwiftStdlib 5.7: macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0"
  "SwiftStdlib 5.8: macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4"
  "SwiftStdlib 5.9: macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0"
  "SwiftStdlib 5.10: macOS 14.4, iOS 17.4, watchOS 10.4, tvOS 17.4, visionOS 1.1"
  "SwiftStdlib 6.0: macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0"
  "SwiftStdlib 6.1: macOS 15.4, iOS 18.4, watchOS 11.4, tvOS 18.4, visionOS 2.4"
  "SwiftStdlib 6.2: macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0"
  "SwiftStdlib 6.3: macOS 26.4, iOS 26.4, watchOS 26.4, tvOS 26.4, visionOS 26.4"
  "SwiftStdlib 6.4: macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0"
  "SwiftStdlib 6.5: macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999"
  )
foreach(def ${availability_defs})
  add_compile_options("$<$<COMPILE_LANGUAGE:Swift>:SHELL:-enable-experimental-feature \"AvailabilityMacro=${def}\">")
endforeach()

add_subdirectory(Sources)

export(EXPORT SwiftPlatformExecutorsTargets
  FILE "cmake/SwiftPlatformExecutors/SwiftPlatformExecutorsTargets.cmake"
  NAMESPACE "SwiftPlatformExecutors::")

add_subdirectory(cmake/modules)
