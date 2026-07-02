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

check_menu_icon "\"WiFi DFU\"" "menu_wifi_dfu"
check_menu_icon "\"delete\".localizedString" "menu_delete"
check_menu_icon "\"information\".localizedString" "menu_information"
check_menu_icon "\"Identify\"" "menu_identify"
check_menu_icon "\"Diagnosis\"" "menu_diagnosis"

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
if [ "$under_development_count" -ne 2 ]; then
  printf 'FAIL: expected WiFi DFU and Diagnosis menu actions to show under development toast, found %s\n' "$under_development_count"
  failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  exit 1
fi

printf 'PASS: WiFi Gateway menu icons, identify action, and information action match expected behavior.\n'
