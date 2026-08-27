#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
source "${repo_root}/scripts/lib/resolve_nordic_sdk_root.sh"
sdk_root="$(resolve_nordic_sdk_root "$repo_root" "${1:-}")"
test_binary="/tmp/SchedulerModelCachePersistenceTests"
read_test_binary="/tmp/SchedulerModelReadCompletionTests"

swiftc -parse-as-library \
  "${sdk_root}/Sources/NordicSigMeshSDK/MeshLib/Node/SchedulerModelCachePersistence.swift" \
  "${sdk_root}/Tests/Standalone/SchedulerModelCachePersistenceTests.swift" \
  -o "${test_binary}"

"${test_binary}"

swiftc -parse-as-library \
  "${sdk_root}/Sources/NordicSigMeshSDK/MeshLib/Manager/SchedulerModelReadCompletion.swift" \
  "${sdk_root}/Tests/Standalone/SchedulerModelReadCompletionTests.swift" \
  -o "${read_test_binary}"

"${read_test_binary}"
