#!/usr/bin/env bash
set -u

file="SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift"
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
  'if sections[section] == .activate {' \
  "Activate section header must avoid the shared GatewaySectionHeaderView constraints."

assert_contains \
  'return UIView()' \
  "Activate section header must return an empty spacing view."

assert_contains \
  'case .activate:' \
  "Activate section must keep a dedicated header height."

assert_contains \
  'return SCRYFrom(16)' \
  "Activate section header height must match the Figma spacing without title constraints."

if [ "$failures" -gt 0 ]; then
  exit 1
fi

printf 'PASS: Gateway Activate header uses an empty spacing view without shared header constraints.\n'
