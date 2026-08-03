#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
test_binary="/tmp/SceneDeleteCapabilityTests"

swiftc -parse-as-library \
  "${repo_root}/SunSmart/Common/Data/SceneDeleteCapability.swift" \
  "${repo_root}/Tests/Scene/SceneDeleteCapabilityTests.swift" \
  -o "${test_binary}"

"${test_binary}"
