#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/EmerFireAlarmMonitorState.swift"

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

assert_contains "$STATE_FILE" "switch status.workingMode" \
  "EFC comprehensive status mapping must branch on device-returned enable_mode."

assert_contains "$STATE_FILE" "case .some(.disabled), .none:" \
  "Disabled and invalid EFC enable_mode must silently display Normal State."

assert_contains "$STATE_FILE" "case .some(.powerLossOnly):" \
  "Power Loss Only mode must have an explicit mapper branch."

assert_contains "$STATE_FILE" "return status.emergencyActive ? .emergencyTriggered : normalState()" \
  "Power Loss Only mode must only respond to em_active."

assert_contains "$STATE_FILE" "case .some(.fireAlarmOnly):" \
  "Fire Alarm Only mode must have an explicit mapper branch."

assert_contains "$STATE_FILE" "return status.fireActive ? .fireTriggered : normalState()" \
  "Fire Alarm Only mode must only respond to fire_active."

assert_contains "$STATE_FILE" "case .some(.powerLossAndFireAlarm):" \
  "Combined mode must have an explicit mapper branch."

assert_contains "$STATE_FILE" "if status.fireActive {" \
  "Combined mode must keep Fire Alarm priority."

assert_contains "$STATE_FILE" "if status.emergencyActive {" \
  "Combined mode must fall back to Power Loss when fire_active is false."

echo "EFC comprehensive status mapping contracts passed."
