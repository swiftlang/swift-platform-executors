#!/bin/bash
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

# Checks that the CMake build compiles the same sources as SwiftPM, since CMake does not discover sources on its own.
#
# The sources are read from the CMake File API of the build directory, which defaults to `build`. The script adds the
# File API query and configures the build directory if needed. An already configured build directory keeps its cache,
# so arguments after `--` only apply when the directory is configured for the first time:
#
#   scripts/check-cmake-sources.sh
#   scripts/check-cmake-sources.sh build -- -DSwiftPlatformExecutors_ENABLE_EXPERIMENTAL_IO=YES

set -euo pipefail

cd "$(dirname "$0")/.."

build_directory=build
if [[ $# -gt 0 && "$1" != "--" ]]; then
  build_directory=$1
  shift
fi
if [[ $# -gt 0 ]]; then
  if [[ "$1" != "--" ]]; then
    echo "usage: $0 [cmake-build-directory] [-- cmake-arguments...]" >&2
    exit 2
  fi
  shift
fi

query_directory="${build_directory}/.cmake/api/v1/query"
reply_directory="${build_directory}/.cmake/api/v1/reply"
if [[ ! -f "${query_directory}/codemodel-v2" || ! -d "${reply_directory}" ]]; then
  mkdir -p "${query_directory}"
  touch "${query_directory}/codemodel-v2"
  if [[ -f "${build_directory}/CMakeCache.txt" ]]; then
    cmake -B "${build_directory}" -S . "$@" >/dev/null
  else
    generator=()
    if command -v ninja >/dev/null; then
      generator=(-G Ninja)
    fi
    cmake ${generator[@]+"${generator[@]}"} -B "${build_directory}" -S . "$@" >/dev/null
  fi
fi

package=$(swift package describe --type json)

status=0
for target in PlatformExecutors CPlatformExecutors; do
  swiftpm=$(jq -r --arg target "${target}" '.targets[] | select(.name == $target) | .sources[]' <<<"${package}" | LC_ALL=C sort)
  cmake=$(cat "${reply_directory}"/target-"${target}"-*.json \
    | jq -r --arg prefix "Sources/${target}/" '.sources[].path | select(startswith($prefix)) | ltrimstr($prefix)' \
    | LC_ALL=C sort -u)
  missing=$(comm -23 <(echo "${swiftpm}") <(echo "${cmake}"))
  extra=$(comm -13 <(echo "${swiftpm}") <(echo "${cmake}"))
  if [[ -n "${missing}${extra}" ]]; then
    echo "error: the CMake sources of ${target} do not match SwiftPM"
    [[ -z "${missing}" ]] || while IFS= read -r source; do echo "  not in CMake: ${source}"; done <<<"${missing}"
    [[ -z "${extra}" ]] || while IFS= read -r source; do echo "  not in SwiftPM: ${source}"; done <<<"${extra}"
    status=1
  else
    echo "${target}: CMake sources match SwiftPM"
  fi
done
exit "${status}"
