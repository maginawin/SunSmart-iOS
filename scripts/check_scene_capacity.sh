#!/bin/zsh
set -euo pipefail
repo_root="${0:A:h:h}"
sdk_root="${repo_root}/.local-sdk/nordic-sig-mesh-sdk"
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/scene-capacity.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library \
  "$repo_root/SunSmart/Common/Data/SceneCapacityPolicy.swift" \
  "$repo_root/SunSmart/Common/Data/SceneDeleteCapability.swift" \
  "$sdk_root/Sources/NordicSigMeshSDK/MeshLib/Scene/SceneRegisterPolicy.swift" \
  "$repo_root/Tests/Scene/SceneCapacityTests.swift" -o "$test_dir/tests"
"$test_dir/tests"
