#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
source "${repo_root}/scripts/lib/resolve_nordic_sdk_root.sh"
sdk_root="$(resolve_nordic_sdk_root "$repo_root" "${1:-}")"
test_binary="/tmp/SiteTimeSetCallSiteContractTests"

swiftc -parse-as-library \
  "${repo_root}/Tests/Site/SiteTimeSetCallSiteContractTests.swift" \
  -o "${test_binary}"

"${test_binary}" \
  "${repo_root}/SunSmart/Common/Data/SiteTimeSetMessageFactory.swift" \
  "${repo_root}/SunSmart/Common/Data/Node+MessageHandles.swift" \
  "${repo_root}/SunSmart/Main/Timed/Model/ScheduleServer.swift" \
  "${repo_root}/SunSmart/Main/Group/Model/GroupServer.swift" \
  "${repo_root}/SunSmart/Main/Space/Model/SyncDevicesCellModel.swift" \
  "${repo_root}/SunSmart/Common/Data/MeshNetwork+SunSmart.swift" \
  "${repo_root}/SunSmart/Main/Device/Controller/DevicesViewController.swift" \
  "${repo_root}/SunSmart/Main/Site/Model/GatewayFastAddTimeInitialization.swift" \
  "${repo_root}/SunSmart/Main/Site/Model/GatewayTimeSyncCoordinator.swift" \
  "${repo_root}/SunSmart.xcodeproj/project.pbxproj" \
  "${sdk_root}/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Messages.swift" \
  "${sdk_root}/Sources/NordicSigMeshSDK/MeshLib/MeshAPI.swift"
