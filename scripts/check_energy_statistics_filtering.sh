#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
policy_source="$repo_root/SunSmart/Main/Energy/Model/EnergyStatisticsFilterPolicy.swift"
policy_test_source="$repo_root/Tests/Energy/EnergyStatisticsFilterPolicyTests.swift"
policy_test_binary="${TMPDIR:-/tmp}/EnergyStatisticsFilterPolicyTests"
contract_test_source="$repo_root/Tests/Energy/EnergyStatisticsFilteringContractTests.swift"
contract_test_binary="${TMPDIR:-/tmp}/EnergyStatisticsFilteringContractTests"

swiftc -parse-as-library "$policy_source" "$policy_test_source" -o "$policy_test_binary"
"$policy_test_binary"

swiftc -parse-as-library "$contract_test_source" -o "$contract_test_binary"
"$contract_test_binary" "$repo_root"
