#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/information-ttl.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library \
  SunSmart/Main/Device/InformationTTLCoordinator.swift \
  Tests/Device/InformationTTLCoordinatorTests.swift \
  -o "$test_dir/InformationTTLCoordinatorTests"
"$test_dir/InformationTTLCoordinatorTests"
plutil -lint SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
