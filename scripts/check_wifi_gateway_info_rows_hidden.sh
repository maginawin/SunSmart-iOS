#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

gateway_controller="SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift"
wifi_controller="SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift"

rg -n "var infoTypes: \\[InfoCellType\\]" "$gateway_controller" >/dev/null \
  || fail "GatewayViewController must expose overridable info row types."

rg -n "return \\[\\.mac, \\.address, \\.model, \\.deviceType, \\.firmwareVersion\\]" "$gateway_controller" >/dev/null \
  || fail "GatewayViewController must keep the default gateway information rows."

rg -n "override var infoTypes: \\[InfoCellType\\]" "$wifi_controller" >/dev/null \
  || fail "WiFiGatewayViewController must override information rows."

rg -n "return \\[\\]" "$wifi_controller" >/dev/null \
  || fail "WiFiGatewayViewController must hide Mac, Address, Model, Device Type, and Firmware rows."

rg -n -F 'sections.filter { $0 != .info }' "$wifi_controller" >/dev/null \
  || fail "WiFiGatewayViewController must remove the empty information section from visible sections."

echo "PASS: WiFi Gateway information rows are hidden."
