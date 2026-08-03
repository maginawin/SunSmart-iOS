#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
sdk_root="${repo_root}/../../nordic-sig-mesh-sdk"
test_binary="/tmp/FreshProvisioningSchedulerStateTests"

swiftc -parse-as-library \
  "${sdk_root}/Sources/NordicSigMeshSDK/MeshLib/Node/FreshProvisioningSchedulerState.swift" \
  "${sdk_root}/Tests/Standalone/FreshProvisioningSchedulerStateTests.swift" \
  -o "${test_binary}"

"${test_binary}"
