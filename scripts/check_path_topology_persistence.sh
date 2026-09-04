#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_source="$repo_root/Tests/Group/PathTopologyPersistenceContractTests.swift"
test_binary="${TMPDIR:-/tmp}/PathTopologyPersistenceContractTests"
policy_source="$repo_root/SunSmart/Main/Group/Model/ProximityLightingTopologyPolicy.swift"
policy_test_source="$repo_root/Tests/Group/ProximityLightingTopologyPolicyTests.swift"
policy_test_binary="${TMPDIR:-/tmp}/ProximityLightingTopologyPolicyTests"
lifecycle_policy_source="$repo_root/SunSmart/Main/Group/Model/ProximityLightingTopologyReconciler.swift"
lifecycle_test_source="$repo_root/Tests/Group/ProximityLightingLifecyclePolicyTests.swift"
lifecycle_test_binary="${TMPDIR:-/tmp}/ProximityLightingLifecyclePolicyTests"
followup_test_source="$repo_root/Tests/Group/SpaceTriggerZoneFollowupContractTests.swift"
followup_test_binary="${TMPDIR:-/tmp}/SpaceTriggerZoneFollowupContractTests"
lifecycle_contract_source="$repo_root/Tests/Group/ProximityLightingLifecycleContractTests.swift"
lifecycle_contract_binary="${TMPDIR:-/tmp}/ProximityLightingLifecycleContractTests"
review_regression_source="$repo_root/Tests/Group/ProximityLightingReviewRegressionContractTests.swift"
review_regression_binary="${TMPDIR:-/tmp}/ProximityLightingReviewRegressionContractTests"

swiftc -parse-as-library "$test_source" -o "$test_binary"
"$test_binary" "$repo_root"

swiftc -parse-as-library "$policy_source" "$policy_test_source" -o "$policy_test_binary"
"$policy_test_binary"

swiftc -parse-as-library "$policy_source" "$lifecycle_policy_source" "$lifecycle_test_source" -o "$lifecycle_test_binary"
"$lifecycle_test_binary"

swiftc -parse-as-library "$followup_test_source" -o "$followup_test_binary"
"$followup_test_binary" "$repo_root"

swiftc -parse-as-library "$lifecycle_contract_source" -o "$lifecycle_contract_binary"
"$lifecycle_contract_binary" "$repo_root"

swiftc -parse-as-library "$review_regression_source" -o "$review_regression_binary"
"$review_regression_binary" "$repo_root"
