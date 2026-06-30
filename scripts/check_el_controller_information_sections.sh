#!/usr/bin/env bash
set -u

file="SunSmart/Main/Device/Controller/DeviceLightViewController.swift"
failures=0

assert_contains() {
  local pattern="$1"
  local message="$2"

  if ! grep -Fq "$pattern" "$file"; then
    printf 'FAIL: %s\n' "$message" >&2
    printf '  expected: %s\n' "$pattern" >&2
    printf '  in file: %s\n' "$file" >&2
    failures=$((failures + 1))
  fi
}

assert_contains \
  'let showsSceneSection = !node.isEmergencySignController' \
  "EL Controller information pages must hide the Scene section."

assert_contains \
  'DeviceInformationViewController(node: self.node, showsSceneSection: showsSceneSection)' \
  "Light detail Information must pass the EL Controller Scene-section visibility to the shared information page."

if [ "$failures" -gt 0 ]; then
  exit 1
fi

printf 'PASS: EL Controller information page hides Scene sections.\n'
