#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

policy="SunSmart/Main/Device/Gateway/Model/GatewayAssociatedSpaceCandidatePolicy.swift"
test_file="Tests/Device/GatewayAssociatedSpaceCandidatePolicyTests.swift"
project_file="SunSmart.xcodeproj/project.pbxproj"
binary="/tmp/GatewayAssociatedSpaceCandidatePolicyTests"

[ -f "$policy" ] || fail "missing Gateway Associated Spaces candidate policy"
[ -f "$test_file" ] || fail "missing Gateway Associated Spaces candidate policy tests"

swiftc -parse-as-library "$policy" "$test_file" -o "$binary"
"$binary"

source_count="$(
  rg -c \
    'C8FA301[1-4]2FD000010000000[1-4] /\* GatewayAssociatedSpaceCandidatePolicy.swift in Sources \*/,' \
    "$project_file" || true
)"
source_count="${source_count:-0}"
[ "$source_count" -eq 4 ] || fail "candidate policy must belong to all four app target source phases"

echo "PASS: Gateway Associated Spaces candidate policy"
