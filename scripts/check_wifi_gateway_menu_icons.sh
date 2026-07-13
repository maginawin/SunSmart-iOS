#!/usr/bin/env bash
set -u

file="SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift"

failures=0

check_menu_icon() {
  local title_expression="$1"
  local icon="$2"
  local pattern

  pattern="UIImage(named: \"${icon}\"), title: ${title_expression}"
  if ! grep -Fq "$pattern" "$file"; then
    printf 'FAIL: expected %s to use %s\n' "$title_expression" "$icon"
    failures=$((failures + 1))
  fi
}

check_menu_icon '"wifi_dfu".localizedString' "menu_wifi_dfu"
check_menu_icon "\"delete\".localizedString" "menu_delete"
check_menu_icon "\"information\".localizedString" "menu_information"
check_menu_icon "\"Identify\"" "menu_identify"

if ! grep -Fq 'private let showsDiagnosisMenuItem = false' "$file"; then
  printf 'FAIL: expected Diagnosis menu item to be retained behind a disabled feature flag\n'
  failures=$((failures + 1))
fi

diagnosis_line=$(grep -Fn 'title: "Diagnosis"' "$file" | cut -d: -f1)
if [ -z "$diagnosis_line" ]; then
  printf 'FAIL: expected Diagnosis menu item implementation to be retained for future enablement\n'
  failures=$((failures + 1))
else
  diagnosis_guard_line=$((diagnosis_line - 1))
  if ! sed -n "${diagnosis_guard_line}p" "$file" | grep -Fq 'if showsDiagnosisMenuItem {'; then
    printf 'FAIL: expected Diagnosis menu item to be hidden behind showsDiagnosisMenuItem\n'
    failures=$((failures + 1))
  fi
fi

identify_count=$(grep -Fc 'MeshAPI.identify(address: self.node.primaryUnicastAddress)' "$file")
if [ "$identify_count" -ne 1 ]; then
  printf 'FAIL: expected Identify menu action to send one SIG Mesh identify command to the WiFi Gateway, found %s\n' "$identify_count"
  failures=$((failures + 1))
fi

if ! grep -Fq 'DeviceInformationViewController(node: self.node, showsGroupSection: false, showsSceneSection: false)' "$file"; then
  printf 'FAIL: expected Information menu action to open WiFi Gateway information without group or scene sections\n'
  failures=$((failures + 1))
fi

under_development_count=$(grep -Fc 'XWHUDManager.showTipHUD("under_development".localizedString, isLineFeed: true)' "$file")
if [ "$under_development_count" -ne 1 ]; then
  printf 'FAIL: expected only Diagnosis menu action to show under development toast, found %s\n' "$under_development_count"
  failures=$((failures + 1))
fi

if ! grep -Fq 'let controller = WiFiFirmwareUpdateViewController()' "$file"; then
  printf 'FAIL: expected WiFi DFU menu action to create WiFiFirmwareUpdateViewController\n'
  failures=$((failures + 1))
fi

if ! grep -Fq 'self.navigationController?.pushViewController(controller, animated: true)' "$file"; then
  printf 'FAIL: expected WiFi DFU menu action to push its controller after menu dismissal\n'
  failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  exit 1
fi

printf 'PASS: WiFi Gateway menu icons, Diagnosis visibility, identify action, and information action match expected behavior.\n'
