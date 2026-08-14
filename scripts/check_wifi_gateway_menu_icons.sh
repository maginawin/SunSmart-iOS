#!/usr/bin/env bash
set -u

gateway_file="SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift"
wifi_file="SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift"
policy_file="SunSmart/Main/Device/Gateway/Model/GatewayMenuPolicy.swift"

failures=0

check_menu_icon() {
  local title_expression="$1"
  local icon="$2"
  local pattern

  pattern="UIImage(named: \"${icon}\"), title: ${title_expression}"
  if ! grep -Fq "$pattern" "$gateway_file"; then
    printf 'FAIL: expected %s to use %s\n' "$title_expression" "$icon"
    failures=$((failures + 1))
  fi
}

check_menu_icon '"4g_dfu".localizedString' "menu_wifi_dfu"
check_menu_icon '"wifi_dfu".localizedString' "menu_wifi_dfu"
check_menu_icon "\"delete\".localizedString" "menu_delete"
check_menu_icon "\"information\".localizedString" "menu_information"
check_menu_icon '"identify".localizedString' "menu_identify"

if ! grep -Fq 'GatewayMenuPolicy.menuActions(' "$gateway_file"; then
  printf 'FAIL: expected shared Gateway menu to consume GatewayMenuPolicy\n'
  failures=$((failures + 1))
fi

if grep -Fq 'title: "Diagnosis"' "$gateway_file" "$wifi_file"; then
  printf 'FAIL: Diagnosis must stay out of the Gateway menus\n'
  failures=$((failures + 1))
fi

identify_count=$(grep -Fc 'MeshAPI.identify(address: self.node.primaryUnicastAddress)' "$gateway_file")
if [ "$identify_count" -ne 1 ]; then
  printf 'FAIL: expected shared Identify action to send one SIG Mesh identify command, found %s\n' "$identify_count"
  failures=$((failures + 1))
fi

if ! grep -Fq 'showsGroupSection: false' "$gateway_file" ||
   ! grep -Fq 'showsSceneSection: false' "$gateway_file" ||
   ! grep -Fq 'gatewayContext: GatewayInformationContext(site: self.site, gateway: self.gateway)' "$gateway_file"; then
  printf 'FAIL: expected shared Information action to open Gateway information without group or scene sections\n'
  failures=$((failures + 1))
fi

under_development_count=$(grep -Fc '"under_development".localizedString' "$gateway_file")
if [ "$under_development_count" -ne 1 ]; then
  printf 'FAIL: expected only 4G DFU to show under development toast, found %s\n' "$under_development_count"
  failures=$((failures + 1))
fi
if grep -Fq '"under_development".localizedString' "$wifi_file"; then
  printf 'FAIL: WiFi Gateway must not use the 4G DFU placeholder toast\n'
  failures=$((failures + 1))
fi

if ! grep -Fq 'override var gatewayFirmwareKind: GatewayFirmwareKind' "$wifi_file" ||
   ! grep -Fq 'return .wifi' "$wifi_file"; then
  printf 'FAIL: expected WiFi Gateway to override the shared firmware kind\n'
  failures=$((failures + 1))
fi

if ! grep -Fq 'let controller = WiFiFirmwareUpdateViewController(node: self.node)' "$wifi_file"; then
  printf 'FAIL: expected WiFi DFU menu action to create WiFiFirmwareUpdateViewController with the current gateway node\n'
  failures=$((failures + 1))
fi

if ! grep -Fq 'navigationController?.pushViewController(controller, animated: true)' "$wifi_file"; then
  printf 'FAIL: expected WiFi DFU menu action to push its controller after menu dismissal\n'
  failures=$((failures + 1))
fi

if ! grep -Fq 'case fourGDFU' "$policy_file" || ! grep -Fq 'case wifiDFU' "$policy_file"; then
  printf 'FAIL: Gateway menu policy must distinguish 4G and WiFi DFU\n'
  failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  exit 1
fi

printf 'PASS: shared Gateway menu icons and actions keep only the DFU behavior device-specific.\n'
