#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

gateway="SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift"
wifi_gateway="SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift"

[ -f "$gateway" ] || fail "missing WiFi Gateway controller"
rg -n 'private var modalDismissalStateBeforeProtectedFlow: Bool\?' "$gateway" >/dev/null || fail "shared Gateway page is missing saved modal dismissal state"
rg -n 'func preventModalStackDismissalUntilReturn\(\)' "$gateway" >/dev/null || fail "shared Gateway page is missing modal dismissal protection helper"
rg -n 'modalDismissalStateBeforeProtectedFlow = navigationController\.isModalInPresentation' "$gateway" >/dev/null || fail "protection helper must preserve the previous state"
rg -n 'navigationController\.isModalInPresentation = true' "$gateway" >/dev/null || fail "protection helper must disable interactive modal dismissal"
rg -n 'private func restoreModalStackDismissalIfNeeded\(\)' "$gateway" >/dev/null || fail "shared Gateway page is missing modal dismissal restoration helper"
rg -n 'navigationController\?\.isModalInPresentation = previousState' "$gateway" >/dev/null || fail "restoration helper must restore the previous state"
rg -n 'override func viewDidAppear\(_ animated: Bool\)' "$gateway" >/dev/null || fail "Gateway page must restore only after it fully reappears"
rg -n 'restoreModalStackDismissalIfNeeded\(\)' "$gateway" >/dev/null || fail "Gateway page does not restore modal dismissal"

base_protection_count=$(grep -Fc 'preventModalStackDismissalUntilReturn()' "$gateway")
[ "$base_protection_count" -eq 2 ] || fail "shared protection helper must be declared once and called by Information once"
wifi_protection_count=$(grep -Fc 'preventModalStackDismissalUntilReturn()' "$wifi_gateway")
[ "$wifi_protection_count" -eq 1 ] || fail "WiFi DFU must call the shared protection helper once"

echo "PASS: shared Gateway Information and WiFi DFU child page modal dismissal checks"
