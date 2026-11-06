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

add_library(CPlatformExecutors STATIC
  shim.c)
target_compile_definitions(CPlatformExecutors PRIVATE
  _GNU_SOURCE)
target_include_directories(CPlatformExecutors PUBLIC
  "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>"
  "$<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}/CPlatformExecutors>")

# The public interface of PlatformExecutors imports this module, so its clients need the header and module map.
install(FILES
  include/CPlatformExecutors.h
  include/module.modulemap
  DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}/CPlatformExecutors")
install(TARGETS CPlatformExecutors
  EXPORT SwiftPlatformExecutorsTargets
  ARCHIVE DESTINATION "${${PROJECT_NAME}_INSTALL_LIBDIR}")
