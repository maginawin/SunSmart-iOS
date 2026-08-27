#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
source "${repo_root}/scripts/lib/resolve_nordic_sdk_root.sh"
sdk_root="$(resolve_nordic_sdk_root "$repo_root" "${1:-}")"
test_binary="${TMPDIR:-/tmp}/SensorCalibrationWorkflowContractTests"

swiftc -parse-as-library \
    "$repo_root/Tests/Group/SensorCalibrationWorkflowContractTests.swift" \
    -o "$test_binary"

"$test_binary" \
    "$repo_root/SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift" \
    "$repo_root/SunSmart/Main/Group/View/LightSensorCalibrationModeView.swift" \
    "$repo_root/SunSmart/en.lproj/Localizable.strings" \
    "$repo_root/SunSmart/zh-Hans.lproj/Localizable.strings" \
    "$sdk_root/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshSensorCalibrateManager.swift" \
    "$sdk_root/Sources/NordicSigMeshSDK/MeshLib/MeshAPI.swift" \
    "$sdk_root/Sources/NordicSigMeshSDK/MeshLib/MeshNetwork/MeshNetworkManager+Create.swift"
