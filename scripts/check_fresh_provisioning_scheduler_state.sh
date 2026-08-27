#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
source "${repo_root}/scripts/lib/resolve_nordic_sdk_root.sh"
sdk_root="$(resolve_nordic_sdk_root "$repo_root" "${1:-}")"
test_binary="/tmp/FreshProvisioningSchedulerStateTests"

swiftc -parse-as-library \
  "${sdk_root}/Sources/NordicSigMeshSDK/MeshLib/Node/FreshProvisioningSchedulerState.swift" \
  "${sdk_root}/Tests/Standalone/FreshProvisioningSchedulerStateTests.swift" \
  -o "${test_binary}"

"${test_binary}"
