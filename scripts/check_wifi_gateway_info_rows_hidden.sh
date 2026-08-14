#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

gateway_controller="SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift"
wifi_controller="SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift"

rg -n -F 'let baseSections: [SectionType] = [.name, .associatedSpaces, .apn, .serverInformation]' "$gateway_controller" >/dev/null \
  || fail "GatewayViewController must hide Mac, Address, Model, Device Type, and Firmware rows for every Gateway."

if rg -n 'super\.sections\.filter \{ \$0 != \.info \}|override var infoTypes' "$wifi_controller" >/dev/null; then
  fail "WiFiGatewayViewController must not duplicate the shared inline-information removal."
fi

echo "PASS: Gateway inline information rows are hidden by the shared base page."
