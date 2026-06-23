#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TARGETS=(
  "SunSmart/Main/Device/Device1.5/FireAlarm"
  "SunSmart/Main/Device/View/DeviceAddTargetSelectView.swift"
  "SunSmart/Main/Space/Controller/SyncDevicesViewController.swift"
)

PATTERN='Waiting for setup|When The Emergency Event|Fire emergency take higher priority|Execution will only begin|Restore AUTO|Repeatedly Send Emergency Control Every|Send Count \(5-second interval\)|Send Count \\|Resuming in \\|You can'\''t choose other devices|Cannot add, type mismatch|Emer&Fire Alarm\\nController|Emer&Fire Controller|title: "Edit"|title: "LINKED"| "LINKED"| "LINK"|Triggered"|Resume"|Inactive"|Scene Publication|Trigger Resend|Restore Resend|Restore Delay|Group Cleanup|Delete Configuration|Action Config|Battery Power Switch:|AC Power Switch:|return "Space"|The device needs to be repaired\.|taskTitle|text: "Action"|Not executed\. No devices in this group\.'

if rg -n "$PATTERN" "${TARGETS[@]}"; then
  echo "FAIL: EFC user-visible hardcoded strings remain."
  exit 1
fi

echo "PASS: no targeted EFC hardcoded strings found."
