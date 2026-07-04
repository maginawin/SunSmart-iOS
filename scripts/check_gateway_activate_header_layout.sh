#!/usr/bin/env bash
set -euo pipefail

gateway_controller="SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift"
wifi_controller="SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

rg -n -F 'let baseSections: [SectionType] = [.name, .info, .associatedSpaces, .apn, .serverInformation]' "$gateway_controller" >/dev/null \
  || fail "GatewayViewController base sections must not include the Activate section."

rg -n -F 'let baseSections: [SectionType] = [.name, .activate, .info, .associatedSpaces, .apn, .serverInformation]' "$gateway_controller" >/dev/null \
  && fail "GatewayViewController must not keep Activate in base sections."

rg -n -F 'guard isNetworkConnectivityVisible, let nameIndex = sections.firstIndex(of: .name) else {' "$wifi_controller" >/dev/null \
  || fail "WiFiGatewayViewController must anchor Network Connectivity below Name."

rg -n -F 'let activateIndex = sections.firstIndex(of: .activate)' "$wifi_controller" >/dev/null \
  && fail "WiFiGatewayViewController must not anchor Network Connectivity to Activate."

rg -n -F 'sections.insert(.networkConnectivity, at: sections.index(after: nameIndex))' "$wifi_controller" >/dev/null \
  || fail "WiFiGatewayViewController must insert Network Connectivity after Name."

echo "PASS: Gateway Activate UI is removed and WiFi Network Connectivity is anchored below Name."
