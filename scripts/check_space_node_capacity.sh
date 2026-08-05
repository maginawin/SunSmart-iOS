#!/usr/bin/env bash
set -euo pipefail

policy="SunSmart/Main/Device/Model/SpaceNodeCapacityPolicy.swift"
policy_tests="Tests/Device/SpaceNodeCapacityPolicyTests.swift"
contract_tests="Tests/Device/SpaceNodeCapacityIntegrationContractTests.swift"
project="SunSmart.xcodeproj/project.pbxproj"
policy_binary="/tmp/SpaceNodeCapacityPolicyTests"
contract_binary="/tmp/SpaceNodeCapacityIntegrationContractTests"

swiftc -parse-as-library "$policy" "$policy_tests" -o "$policy_binary"
"$policy_binary"

if [ -f "$contract_tests" ]; then
    swiftc -parse-as-library "$contract_tests" -o "$contract_binary"
    "$contract_binary" "$PWD"
fi

source_count="$(rg -c 'SpaceNodeCapacityPolicy.swift in Sources \*/,$' "$project")"
if [ "$source_count" -ne 4 ]; then
    printf 'FAIL: SpaceNodeCapacityPolicy must belong to all four app targets.\n' >&2
    exit 1
fi

printf 'PASS: Space Node capacity policy and target membership.\n'
