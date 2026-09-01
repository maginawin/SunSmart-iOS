#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
source "${repo_root}/scripts/lib/resolve_nordic_sdk_root.sh"
sdk_root="$(resolve_nordic_sdk_root "$repo_root" "${1:-}")"
test_binary="/tmp/NodeCreatedTimestampContractTests"

swiftc -parse-as-library \
  "${repo_root}/Tests/Data/NodeCreatedTimestampContractTests.swift" \
  -o "${test_binary}"

"${test_binary}" \
  "${sdk_root}/Sources/NordicSigMeshSDK/nRFMeshProvision/Mesh Model/Node.swift" \
  "${sdk_root}/Sources/NordicSigMeshSDK/MeshLib/MeshDatabase.swift" \
  "${repo_root}/SunSmart/Common/Data/ExportData.swift" \
  "${repo_root}/SunSmart/Common/Data/ImportData.swift" \
  "${repo_root}/SunSmart/Common/Network/NetowrkReqeustApi.swift"
