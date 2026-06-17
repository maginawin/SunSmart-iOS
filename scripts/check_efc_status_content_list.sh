#!/usr/bin/env bash
set -euo pipefail

assert_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"

  if ! grep -q "$pattern" "$file"; then
    echo "FAIL: $message" >&2
    echo "  expected pattern: $pattern" >&2
    echo "  in file: $file" >&2
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"

  if grep -q "$pattern" "$file"; then
    echo "FAIL: $message" >&2
    echo "  unexpected pattern: $pattern" >&2
    echo "  in file: $file" >&2
    exit 1
  fi
}

STATE_FILE="SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/EmerFireAlarmMonitorState.swift"
SET_VIEW_FILE="SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireAlarmStatusSetView.swift"
CELL_FILE="SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireAlarmStatusItemCell.swift"
STRINGS_FILE="SunSmart/en.lproj/Localizable.strings"

assert_contains "$STATE_FILE" '"fire_alarm_occurs".localizedString' \
  "Status list must display Fire alarm occurs."
assert_contains "$STATE_FILE" '"power_supply_fails".localizedString' \
  "Status list must display Power supply fails."
assert_contains "$STATE_FILE" '"emergency_event_ends".localizedString' \
  "Status list must display Emergency event ends."
assert_contains "$STATE_FILE" 'restoreActionTitle(for:' \
  "Status list must derive a dynamic restore action title."
assert_contains "$STATE_FILE" 'case .restoreAuto:' \
  "Restore AUTO must have an explicit display value."
assert_contains "$STATE_FILE" 'case .setBrightness:' \
  "Set brightness restore must have an explicit display value."
assert_contains "$STATE_FILE" 'case .none:' \
  "None restore must have an explicit display value."

assert_not_contains "$STATE_FILE" '"power_is_restored".localizedString' \
  "Status list must not display Power is restored."
assert_not_contains "$STATE_FILE" '"fire_alarm_stops".localizedString' \
  "Status list must not display Fire alarm stops."

assert_contains "$SET_VIEW_FILE" 'struct DetailViewModel' \
  "Status set view item model must support multiple detail/value rows."
assert_contains "$SET_VIEW_FILE" 'details:' \
  "Status set view must pass detail/value rows to the cell."
assert_contains "$CELL_FILE" 'detailStackView' \
  "Status item cell must render multiple detail/value rows."
assert_contains "$CELL_FILE" 'rightValueStackView' \
  "Status item cell must align multiple right-side values."

assert_contains "$STRINGS_FILE" '"emergency_event_ends" = "Emergency event ends";' \
  "English strings must include Emergency event ends."
assert_contains "$STRINGS_FILE" '"restore_auto" = "Auto";' \
  "English strings must include Auto restore action."
assert_contains "$STRINGS_FILE" '"restore_none" = "None";' \
  "English strings must include None restore action."
assert_contains "$STRINGS_FILE" '"set_brightness_to_value" = "Set Brightness To %@";' \
  "English strings must include Set Brightness action format."

echo "EFC status content list contracts passed."
