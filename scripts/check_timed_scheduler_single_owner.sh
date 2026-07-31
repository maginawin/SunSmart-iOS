#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
sdk_root="${repo_root}/../../nordic-sig-mesh-sdk"
test_binary="/tmp/TimedSchedulerSingleOwnerContractTests"
policy_test_binary="/tmp/TimedSchedulerOwnerPolicyTests"

swiftc -parse-as-library \
  "${repo_root}/SunSmart/Main/Timed/Model/TimedSchedulerOwnerPolicy.swift" \
  "${repo_root}/Tests/Timed/TimedSchedulerOwnerPolicyTests.swift" \
  -o "${policy_test_binary}"

"${policy_test_binary}"

swiftc -parse-as-library \
  "${repo_root}/Tests/Timed/TimedSchedulerSingleOwnerContractTests.swift" \
  -o "${test_binary}"

"${test_binary}" \
  "${sdk_root}/Sources/NordicSigMeshSDK/MeshLib/Node/Node+SupportModels.swift" \
  "${sdk_root}/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Messages.swift" \
  "${sdk_root}/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshScheduleServer.swift" \
  "${repo_root}/SunSmart/Common/Data/Node+MessageHandles.swift" \
  "${repo_root}/SunSmart/Common/Data/MeshNetwork+SunSmart.swift" \
  "${repo_root}/SunSmart/Main/Timed/Model/ScheduleServer.swift" \
  "${repo_root}/SunSmart/Main/Group/Model/GroupServer.swift" \
  "${repo_root}/SunSmart/Main/Timed/Model/Scheduler.swift" \
  "${repo_root}/SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift" \
  "${sdk_root}/Sources/NordicSigMeshSDK/MeshLib/MeshDatabase.swift" \
  "${repo_root}/SunSmart/Main/Timed/Controller/TimedViewController.swift"
