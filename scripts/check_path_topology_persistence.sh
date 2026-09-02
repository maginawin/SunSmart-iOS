#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_source="$repo_root/Tests/Group/PathTopologyPersistenceContractTests.swift"
test_binary="${TMPDIR:-/tmp}/PathTopologyPersistenceContractTests"
policy_source="$repo_root/SunSmart/Main/Group/Model/ProximityLightingTopologyPolicy.swift"
policy_test_source="$repo_root/Tests/Group/ProximityLightingTopologyPolicyTests.swift"
policy_test_binary="${TMPDIR:-/tmp}/ProximityLightingTopologyPolicyTests"
followup_test_source="$repo_root/Tests/Group/SpaceTriggerZoneFollowupContractTests.swift"
followup_test_binary="${TMPDIR:-/tmp}/SpaceTriggerZoneFollowupContractTests"

swiftc -parse-as-library "$test_source" -o "$test_binary"
"$test_binary" "$repo_root"

swiftc -parse-as-library "$policy_source" "$policy_test_source" -o "$policy_test_binary"
"$policy_test_binary"

swiftc -parse-as-library "$followup_test_source" -o "$followup_test_binary"
"$followup_test_binary" "$repo_root"
