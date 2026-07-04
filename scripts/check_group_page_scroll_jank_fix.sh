#!/usr/bin/env bash
set -euo pipefail

assert_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if ! rg -q "$pattern" "$file"; then
    echo "FAIL: $message"
    echo "  file: $file"
    echo "  expected pattern: $pattern"
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if rg -q "$pattern" "$file"; then
    echo "FAIL: $message"
    echo "  file: $file"
    echo "  unexpected pattern: $pattern"
    exit 1
  fi
}

ratio_file="SunSmart/Main/Device/View/DeviceUpDownRatioControlView.swift"
group_file="SunSmart/Main/Group/Controller/GroupViewController.swift"

assert_contains "$ratio_file" "guard clampedValue != currentUpValue" "Up/down ratio control must skip duplicate value refreshes"
assert_contains "$ratio_file" "guard normalizedValue != self\\.selectedValue" "Quick ratio buttons must skip duplicate selection refreshes"
assert_not_contains "$ratio_file" "layoutIfNeeded\\(\\)" "Up/down ratio control must not force synchronous layout during value refresh"
assert_not_contains "$ratio_file" "make\\.width\\.equalTo\\(SCRXFrom\\(56\\)\\)" "Quick ratio buttons must not use fixed widths that conflict in narrow layouts"
assert_contains "$ratio_file" "\\.fillEqually" "Quick ratio buttons must size responsively inside the stack view"

assert_contains "$group_file" "nodeIndexByAddress" "Group page must cache node index lookup by address"
assert_contains "$group_file" "cachedGroupControlCCTNodes" "Group page must cache CCT-capable nodes"
assert_contains "$group_file" "cachedUpDownRatioNodes" "Group page must cache up/down-ratio capable nodes"
assert_contains "$group_file" "rebuildGroupDerivedCache" "Group page must rebuild derived caches when group data changes"
assert_contains "$group_file" "isSensorOnlyMessage" "Group page must classify sensor-only messages"
assert_contains "$group_file" "if isSensorOnlyMessage\\(message\\)[[:space:]]*\\{[[:space:]]*return[[:space:]]*\\}" "Sensor-only messages must return before collection/control refresh"
assert_contains "$group_file" "updateGroupControlSummaryIfNeeded" "Group control summary refresh must be centralized"
assert_contains "$group_file" "lastShowsUpDownRatioControl" "Group page must avoid remaking ratio/control constraints when visibility is unchanged"

echo "PASS: Group page scroll jank fix contract"
