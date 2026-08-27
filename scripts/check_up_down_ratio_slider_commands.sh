#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

scheduler="SunSmart/Main/Device/Model/UpDownRatioCommandScheduler.swift"
scheduler_tests="Tests/Device/UpDownRatioCommandSchedulerTests.swift"
ratio_view="SunSmart/Main/Device/View/DeviceUpDownRatioControlView.swift"
device_controller="SunSmart/Main/Device/Controller/DeviceLightViewController.swift"
group_controller="SunSmart/Main/Group/Controller/GroupViewController.swift"
slider="SunSmart/Common/View/CustomDeviceSlider.swift"
project_file="SunSmart.xcodeproj/project.pbxproj"
test_binary="/tmp/UpDownRatioCommandSchedulerTests"

swiftc -parse-as-library "$scheduler" "$scheduler_tests" -o "$test_binary"
"$test_binary"

rg -n 'var valueSampled: \(\(Int\) -> Void\)\?' "$ratio_view" >/dev/null \
  || fail "Ratio view must expose a sampling callback"
rg -n 'sliderView\.slider\.interval = 0\.3' "$ratio_view" >/dev/null \
  || fail "Ratio slider must use the confirmed 0.3 second interval"
rg -n 'sliderView\.slider\.sendsFinalValueOnTouchCancel = true' "$ratio_view" >/dev/null \
  || fail "Ratio slider must deliver a final value when tracking is cancelled"
rg -n 'if ended' "$ratio_view" >/dev/null \
  || fail "Ratio view must distinguish final from sampling callbacks"
rg -n 'valueChanged\?\(upValue\)' "$ratio_view" >/dev/null \
  || fail "Ratio final callback must bypass UI value deduplication"
rg -n 'valueSampled\?\(upValue\)' "$ratio_view" >/dev/null \
  || fail "Ratio sampling callback must forward the throttled value"
rg -n 'override func touchesCancelled' "$slider" >/dev/null \
  || fail "Cancelled slider tracking must finish with a final callback"
rg -n 'var sendsFinalValueOnTouchCancel = false' "$slider" >/dev/null \
  || fail "Touch-cancel final delivery must stay opt-in for non-Ratio sliders"

rg -n 'upDownRatioView\.valueSampled' "$device_controller" >/dev/null \
  || fail "Device page must consume Ratio sampling values"
rg -n 'UpDownRatioCommandScheduler' "$device_controller" >/dev/null \
  || fail "Device page must serialize Ratio Vendor commands"
rg -n 'upDownRatioControlView\.valueSampled' "$group_controller" >/dev/null \
  || fail "Group page must consume Ratio sampling values"
rg -n 'sendGroupUpRatioValue\(value, persist: false\)' "$group_controller" >/dev/null \
  || fail "Group sampling must send without persisting"
rg -n 'sendGroupUpRatioValue\(value, persist: true\)' "$group_controller" >/dev/null \
  || fail "Group final must send and persist"
rg -n 'MeshAPI\.sendMessage\(' "$group_controller" >/dev/null \
  || fail "Group Ratio must keep the fire-and-forget Mesh sender"

build_file_count="$(rg -c 'UpDownRatioCommandScheduler\.swift in Sources' "$project_file" || true)"
[[ "$build_file_count" -eq 8 ]] \
  || fail "Project must contain four scheduler build-file declarations and four Sources memberships"
file_reference_count="$(rg -c 'path = UpDownRatioCommandScheduler\.swift;' "$project_file" || true)"
[[ "$file_reference_count" -eq 1 ]] \
  || fail "Project must contain exactly one scheduler file reference"

echo "PASS: Up/Down Ratio slider command checks completed."
