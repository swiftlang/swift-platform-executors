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

include_guard()

include(FetchContent)

# Inside a larger build, such as the Swift toolchain, the dependencies are found by `find_package`. Standalone builds
# fetch them at the versions that Package.swift depends on, as `swift package describe` reports them, so that the CMake
# and SwiftPM builds use the same versions.

# Returns the URL and the exact version, branch or revision of a dependency of Package.swift. Package.swift is described
# with the `swift` of the Swift compiler that CMake uses, once per configuration.
function(_swift_platform_executors_package_dependency identity out_url out_tag)
  get_property(description GLOBAL PROPERTY _SwiftPlatformExecutors_PACKAGE_DESCRIPTION)
  if(NOT description)
    cmake_path(GET CMAKE_Swift_COMPILER PARENT_PATH swift_bin_dir)
    find_program(SwiftPlatformExecutors_SWIFT_EXECUTABLE swift HINTS "${swift_bin_dir}" REQUIRED)
    execute_process(
      COMMAND "${SwiftPlatformExecutors_SWIFT_EXECUTABLE}" package --package-path "${PROJECT_SOURCE_DIR}"
        describe --type json
      OUTPUT_VARIABLE description
      ERROR_VARIABLE error
      RESULT_VARIABLE result)
    if(NOT result EQUAL 0)
      message(FATAL_ERROR "`swift package describe` failed: ${error}")
    endif()
    set_property(GLOBAL PROPERTY _SwiftPlatformExecutors_PACKAGE_DESCRIPTION "${description}")
    # Picks up changes to the dependencies.
    set_property(DIRECTORY "${PROJECT_SOURCE_DIR}" APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${PROJECT_SOURCE_DIR}/Package.swift")
  endif()

  string(JSON count LENGTH "${description}" dependencies)
  math(EXPR last "${count} - 1")
  foreach(index RANGE ${last})
    string(JSON dependency GET "${description}" dependencies ${index} identity)
    if(dependency STREQUAL identity)
      string(JSON url GET "${description}" dependencies ${index} url)
      string(JSON kind MEMBER "${description}" dependencies ${index} requirement 0)
      if(NOT kind MATCHES "^(exact|branch|revision)$")
        message(FATAL_ERROR "Package.swift depends on ${identity} with a `${kind}` requirement, but the CMake build "
          "needs an exact version, a branch or a revision to fetch.")
      endif()
      string(JSON tag GET "${description}" dependencies ${index} requirement ${kind} 0)
      set(${out_url} "${url}" PARENT_SCOPE)
      set(${out_tag} "${tag}" PARENT_SCOPE)
      return()
    endif()
  endforeach()
  message(FATAL_ERROR "Package.swift does not depend on ${identity}.")
endfunction()

# swift-collections is always needed (BasicContainers); the I/O interfaces also use DequeModule and the
# UnstableHashedContainers trait.
find_package(SwiftCollections QUIET)
if(NOT SwiftCollections_FOUND)
  _swift_platform_executors_package_dependency(swift-collections collections_url collections_tag)
  message("-- Vendoring swift-collections ${collections_tag}")
  # Like Package.swift, which enables the UnstableHashedContainers trait for the I/O interfaces.
  set(COLLECTIONS_ENABLE_HASHED_CONTAINERS ${SwiftPlatformExecutors_ENABLE_EXPERIMENTAL_IO} CACHE BOOL "" FORCE)
  FetchContent_Declare(SwiftCollections
    GIT_REPOSITORY "${collections_url}"
    GIT_TAG "${collections_tag}"
    GIT_SHALLOW YES)
  list(APPEND VendoredDependencies SwiftCollections)
endif()

if(SwiftPlatformExecutors_ENABLE_EXPERIMENTAL_IO_URING)
  find_package(SwiftSystem QUIET)
  if(NOT SwiftSystem_FOUND)
    _swift_platform_executors_package_dependency(swift-system system_url system_tag)
    message("-- Vendoring swift-system ${system_tag}")
    FetchContent_Declare(SwiftSystem
      GIT_REPOSITORY "${system_url}"
      GIT_TAG "${system_tag}"
      GIT_SHALLOW YES)
    list(APPEND VendoredDependencies SwiftSystem)
  endif()
endif()

if(VendoredDependencies)
  FetchContent_MakeAvailable(${VendoredDependencies})
endif()

# swift-collections' CMake build only has the COLLECTIONS_ENABLE_HASHED_CONTAINERS option from 1.7.3 on, so the
# UnstableHashedContainers trait is also passed to BasicContainers directly.
if(SwiftPlatformExecutors_ENABLE_EXPERIMENTAL_IO AND SwiftCollections IN_LIST VendoredDependencies)
  target_compile_options(BasicContainers PRIVATE "$<$<COMPILE_LANGUAGE:Swift>:-DUnstableHashedContainers>")
endif()

# The dependencies' build trees only define the targets without their namespace.
foreach(target BasicContainers DequeModule)
  if(NOT TARGET SwiftCollections::${target})
    add_library(SwiftCollections::${target} ALIAS ${target})
  endif()
endforeach()
foreach(target SystemPackage SystemSockets)
  if(SwiftPlatformExecutors_ENABLE_EXPERIMENTAL_IO_URING AND NOT TARGET SwiftSystem::${target})
    if(NOT TARGET ${target})
      message(FATAL_ERROR "swift-system does not provide the ${target} target. The io_uring backend requires SystemSockets, which swift-system does not build with CMake yet.")
    endif()
    add_library(SwiftSystem::${target} ALIAS ${target})
  endif()
endforeach()
