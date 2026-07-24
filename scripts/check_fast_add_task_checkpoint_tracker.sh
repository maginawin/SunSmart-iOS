#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

tracker="SunSmart/Main/Device/Model/FastAddTaskCheckpointTracker.swift"
test_file="Tests/Device/FastAddTaskCheckpointTrackerTests.swift"
project_file="SunSmart.xcodeproj/project.pbxproj"
binary="/tmp/FastAddTaskCheckpointTrackerTests"

[ -f "$tracker" ] || fail "missing FastAddTaskCheckpointTracker source"
[ -f "$test_file" ] || fail "missing FastAddTaskCheckpointTracker tests"

swiftc -parse-as-library "$tracker" "$test_file" -o "$binary"
"$binary"

source_count="$(rg -c 'C8FA20[1-4]12F12000100000001 /\* FastAddTaskCheckpointTracker.swift in Sources \*/,' "$project_file")"
[ "$source_count" -eq 4 ] || fail "tracker must belong to all four app target source phases"

rg -n 'FastAddTaskCheckpointTracker.swift' "$project_file" >/dev/null \
  || fail "tracker file reference missing from project"

echo "PASS: Fast Add task checkpoint tracker"
