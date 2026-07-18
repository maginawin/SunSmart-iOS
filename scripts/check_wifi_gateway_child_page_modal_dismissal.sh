#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

gateway="SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift"

[ -f "$gateway" ] || fail "missing WiFi Gateway controller"
rg -n 'private var modalDismissalStateBeforeProtectedFlow: Bool\?' "$gateway" >/dev/null || fail "missing saved modal dismissal state"
rg -n 'private func preventModalStackDismissalUntilReturn\(\)' "$gateway" >/dev/null || fail "missing modal dismissal protection helper"
rg -n 'modalDismissalStateBeforeProtectedFlow = navigationController\.isModalInPresentation' "$gateway" >/dev/null || fail "protection helper must preserve the previous state"
rg -n 'navigationController\.isModalInPresentation = true' "$gateway" >/dev/null || fail "protection helper must disable interactive modal dismissal"
rg -n 'private func restoreModalStackDismissalIfNeeded\(\)' "$gateway" >/dev/null || fail "missing modal dismissal restoration helper"
rg -n 'navigationController\?\.isModalInPresentation = previousState' "$gateway" >/dev/null || fail "restoration helper must restore the previous state"
rg -n 'override func viewDidAppear\(_ animated: Bool\)' "$gateway" >/dev/null || fail "Gateway page must restore only after it fully reappears"
rg -n 'restoreModalStackDismissalIfNeeded\(\)' "$gateway" >/dev/null || fail "Gateway page does not restore modal dismissal"

protection_call_count=$(grep -Fc 'preventModalStackDismissalUntilReturn()' "$gateway")
[ "$protection_call_count" -eq 3 ] || fail "protection helper must be declared once and called by exactly two menu entries"

echo "PASS: WiFi/4G Gateway child page modal dismissal checks"
