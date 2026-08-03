#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

policy="SunSmart/Main/Device/Model/DeviceRestoreCandidatePolicy.swift"
test_file="Tests/Device/DeviceRestoreCandidatePolicyTests.swift"
recovery_policy="SunSmart/Main/Device/Model/DeviceRestoreEFCRecoveryPolicy.swift"
recovery_test_file="Tests/Device/DeviceRestoreEFCRecoveryPolicyTests.swift"
project_file="SunSmart.xcodeproj/project.pbxproj"
binary="/tmp/DeviceRestoreCandidatePolicyTests"
recovery_binary="/tmp/DeviceRestoreEFCRecoveryPolicyTests"

[ -f "$policy" ] || fail "missing Restore Device Data candidate policy"
[ -f "$test_file" ] || fail "missing Restore Device Data candidate policy tests"
[ -f "$recovery_policy" ] || fail "missing EFC recovery policy"
[ -f "$recovery_test_file" ] || fail "missing EFC recovery policy tests"

swiftc -parse-as-library "$policy" "$test_file" -o "$binary"
"$binary"
swiftc -parse-as-library "$policy" "$recovery_policy" "$recovery_test_file" -o "$recovery_binary"
"$recovery_binary"

source_count="$({
  rg -c \
    'C8FA401[1-4]2FD000030000000[1-4] /\* DeviceRestoreCandidatePolicy.swift in Sources \*/,' \
    "$project_file" || true
})"
source_count="${source_count:-0}"
[ "$source_count" -eq 4 ] || fail "candidate policy must belong to all four app target source phases"

rg -n 'DeviceRestoreCandidatePolicy.swift' "$project_file" >/dev/null \
  || fail "candidate policy file reference missing from project"

recovery_source_count="$({
  rg -c \
    'C8FA402[1-4]2FD000030000000[1-4] /\* DeviceRestoreEFCRecoveryPolicy.swift in Sources \*/,' \
    "$project_file" || true
})"
recovery_source_count="${recovery_source_count:-0}"
[ "$recovery_source_count" -eq 4 ] || fail "EFC recovery policy must belong to all four app target source phases"

rg -n 'DeviceRestoreEFCRecoveryPolicy.swift' "$project_file" >/dev/null \
  || fail "EFC recovery policy file reference missing from project"

echo "PASS: Restore Device Data EFC support"
