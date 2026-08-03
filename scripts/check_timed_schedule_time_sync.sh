#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
test_binary="/tmp/TimedScheduleTimeSyncPolicyTests"

swiftc -parse-as-library \
  "${repo_root}/SunSmart/Common/Data/TimedScheduleTimeSyncPolicy.swift" \
  "${repo_root}/Tests/Timed/TimedScheduleTimeSyncPolicyTests.swift" \
  -o "${test_binary}"

"${test_binary}"
