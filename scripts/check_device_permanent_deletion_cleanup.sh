#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
test_binary="/tmp/DeviceScheduleAddressCleanupTests"

swiftc -parse-as-library \
  "${repo_root}/SunSmart/Main/Timed/Model/TimedSchedulerSlotPolicy.swift" \
  "${repo_root}/SunSmart/Main/Scene/Model/SceneConfiguration.swift" \
  "${repo_root}/SunSmart/Common/Data/HDBConfiguration.swift" \
  "${repo_root}/SunSmart/Common/Data/HDBLightingZonePolicy.swift" \
  "${repo_root}/SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift" \
  "${repo_root}/SunSmart/Common/Data/DeviceScheduleAddressCleanup.swift" \
  "${repo_root}/Tests/Device/DeviceScheduleAddressCleanupTests.swift" \
  -o "${test_binary}"

"${test_binary}"
