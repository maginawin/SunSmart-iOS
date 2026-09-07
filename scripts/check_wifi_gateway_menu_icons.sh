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

if grep -Fq '"under_development".localizedString' "$gateway_file" "$wifi_file"; then
  printf 'FAIL: displayed Gateway DFU menus must enter their firmware flow\n'
  failures=$((failures + 1))
fi

if ! grep -Fq 'override var gatewayFirmwareKind: GatewayFirmwareKind' "$wifi_file" ||
   ! grep -Fq 'return .wifi' "$wifi_file"; then
  printf 'FAIL: expected WiFi Gateway to override the shared firmware kind\n'
  failures=$((failures + 1))
fi

if ! grep -Fq 'let controller = WiFiFirmwareUpdateViewController(node: node, firmwareKind: firmwareKind)' "$gateway_file"; then
  printf 'FAIL: expected WiFi DFU menu action to create WiFiFirmwareUpdateViewController with the current gateway node\n'
  failures=$((failures + 1))
fi

if ! grep -Fq 'navigationController?.pushViewController(controller, animated: true)' "$gateway_file"; then
  printf 'FAIL: expected WiFi DFU menu action to push its controller after menu dismissal\n'
  failures=$((failures + 1))
fi

if ! grep -Fq 'case fourGDFU' "$policy_file" || ! grep -Fq 'case wifiDFU' "$policy_file"; then
  printf 'FAIL: Gateway menu policy must distinguish 4G and WiFi DFU\n'
  failures=$((failures + 1))
fi

python3 - <<'PY_ROUTING' || exit 1
from pathlib import Path
source = Path("SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift").read_text()
for action, next_action, title, kind in [
    ("fourGDFU", "wifiDFU", "4g_dfu", "fourG"),
    ("wifiDFU", "delete", "wifi_dfu", "wifi"),
]:
    block = source.split(f"case .{action}:", 1)[1].split(f"case .{next_action}:", 1)[0]
    assert f'title: "{title}".localizedString' in block
    assert f"performGatewayDFUAction(firmwareKind: .{kind})" in block
    assert "performsActionAfterDismiss: true" in block
route = source.split("private func performGatewayDFUAction(", 1)[1].split("func preventModalStackDismissalUntilReturn", 1)[0]
assert "productIdentifier" not in route
assert "gatewayFirmwareKind" not in route
assert "preventModalStackDismissalUntilReturn()" in route
wifi = Path("SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift").read_text()
assert "override func performGatewayDFUAction" not in wifi
policy = Path("SunSmart/Main/Device/Gateway/Model/GatewayMenuPolicy.swift").read_text()
assert "supportsFourGDFU" not in policy
print("Gateway DFU menu routing checks passed")
PY_ROUTING

swiftc -parse-as-library "$policy_file" Tests/Device/GatewayMenuPolicyTests.swift -o /tmp/FixGatewayMenuPolicyTests || exit 1
/tmp/FixGatewayMenuPolicyTests || exit 1

if [ "$failures" -gt 0 ]; then
  exit 1
fi

printf 'PASS: shared Gateway menu icons and actions keep only the DFU behavior device-specific.\n'
