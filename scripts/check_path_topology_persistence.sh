#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_source="$repo_root/Tests/Group/PathTopologyPersistenceContractTests.swift"
test_binary="${TMPDIR:-/tmp}/PathTopologyPersistenceContractTests"

swiftc -parse-as-library "$test_source" -o "$test_binary"
"$test_binary" "$repo_root"
