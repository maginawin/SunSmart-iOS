#!/usr/bin/env bash
set -u

light_file="SunSmart/Main/Device/Controller/DeviceLightViewController.swift"
power_switch_file="SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift"
wifi_gateway_file="SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift"

failures=0

check_menu_icon() {
  local file="$1"
  local title_expression="$2"
  local icon="$3"
  local pattern

  pattern="UIImage(named: \"${icon}\"), title: ${title_expression}"
  if ! grep -Fq "$pattern" "$file"; then
    printf 'FAIL: expected %s in %s to use %s\n' "$title_expression" "$file" "$icon"
    failures=$((failures + 1))
  fi
}

check_menu_icon "$light_file" "\"set_proxy\".localizedString" "menu_set_proxy"
check_menu_icon "$light_file" "\"identify\".localizedString" "menu_identify"
check_menu_icon "$light_file" "\"reboot\".localizedString" "menu_firmware_update"

check_menu_icon "$power_switch_file" "\"Identify\"" "menu_identify"
check_menu_icon "$wifi_gateway_file" "\"Identify\"" "menu_identify"

if [ "$failures" -gt 0 ]; then
  exit 1
fi

printf 'PASS: device menu icons match expected assets.\n'
