#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

parent="SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift"
history="SunSmart/Main/Firmware/Controller/FirmwareVersionHistoryController.swift"
beta="SunSmart/Main/Firmware/View/BetaTestingAlertView.swift"
wifi="SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift"
gateway="SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift"
project="SunSmart.xcodeproj/project.pbxproj"
localizable_en="SunSmart/en.lproj/Localizable.strings"
localizable_zh="SunSmart/zh-Hans.lproj/Localizable.strings"

rg -n 'var firmwarePageTitle: String' "$parent" >/dev/null || fail "missing firmware page title hook"
rg -n 'var firmwareRequestCustomId: String' "$parent" >/dev/null || fail "missing firmware customer id hook"
rg -n 'var displayedCurrentTargetVersion: String\?' "$parent" >/dev/null || fail "missing displayed current version hook"
rg -n 'var showsFirmwareDeleteButton: Bool' "$parent" >/dev/null || fail "missing delete visibility hook"
rg -n 'var showsBetaImportAction: Bool' "$parent" >/dev/null || fail "missing beta import visibility hook"
rg -n 'var firmwarePrimaryActionTitle: String' "$parent" >/dev/null || fail "missing primary action title hook"
rg -n '@objc func firmwarePrimaryAction\(\)' "$parent" >/dev/null || fail "missing primary action hook"
rg -n 'customId: firmwareRequestCustomId' "$parent" >/dev/null || fail "latest request ignores customer id hook"
rg -n 'showsImportAction: showsBetaImportAction' "$parent" >/dev/null || fail "beta alert ignores import visibility hook"
rg -n 'title: firmwarePrimaryActionTitle' "$parent" >/dev/null || fail "button ignores title hook"
rg -n '#selector\(firmwarePrimaryAction\)' "$parent" >/dev/null || fail "button ignores action hook"
rg -n 'showsImportAction: Bool = true' "$beta" >/dev/null || fail "beta alert missing default import visibility"
rg -n 'importBtn\.isHidden = !showsImportAction' "$beta" >/dev/null || fail "beta alert does not apply import visibility"

rg -n 'let customId: String' "$history" >/dev/null || fail "history missing string customer id"
rg -n 'init\(productId: UInt16, customId: String = "00"\)' "$history" >/dev/null || fail "history initializer missing default customer id"
rg -n 'customId: self\.customId' "$history" >/dev/null || fail "history request ignores customer id"
customer_id_hook_count=$(grep -Fc 'customId: firmwareRequestCustomId' "$parent")
[ "$customer_id_hook_count" -eq 2 ] || fail "latest and history requests must both use the customer id hook"

[ -f "$wifi" ] || fail "missing WiFi firmware update controller"
rg -n 'final class WiFiFirmwareUpdateViewController: FirmwareVersionViewController' "$wifi" >/dev/null || fail "WiFi firmware controller must inherit FirmwareVersionViewController"
rg -n 'override var firmwareRequestCustomId: String' "$wifi" >/dev/null || fail "WiFi firmware controller missing customer id override"
rg -n 'return "wifi"' "$wifi" >/dev/null || fail "WiFi firmware customer id must be wifi"
rg -n 'override var displayedCurrentTargetVersion: String\?' "$wifi" >/dev/null || fail "WiFi firmware controller missing fixed current version"
rg -n 'return "1\.0\.0"' "$wifi" >/dev/null || fail "WiFi firmware current version must be 1.0.0"
rg -n 'override var showsFirmwareDeleteButton: Bool' "$wifi" >/dev/null || fail "WiFi firmware controller missing delete visibility override"
rg -n 'override var showsBetaImportAction: Bool' "$wifi" >/dev/null || fail "WiFi firmware controller missing beta import visibility override"
rg -n 'override var firmwarePrimaryActionTitle: String' "$wifi" >/dev/null || fail "WiFi firmware controller missing primary action title override"
rg -n '@objc override func firmwarePrimaryAction\(\)' "$wifi" >/dev/null || fail "WiFi firmware controller missing primary action override"
rg -n 'XWHUDManager\.showTipHUD\("under_development"\.localizedString' "$wifi" >/dev/null || fail "WiFi upgrade placeholder is missing"
if rg -n 'FirmwareData\.(load|save|delete)|ZipHandler|UIDocumentPickerViewController' "$wifi" >/dev/null; then
  fail "WiFi firmware controller must not download, import, save, or delete firmware"
fi

grep -Fq '"wifi_dfu" = "WiFi DFU";' "$localizable_en" || fail "missing English WiFi DFU localization"
grep -Fq '"wifi_firmware_update" = "WiFi Firmware Update";' "$localizable_en" || fail "missing English WiFi firmware title localization"
grep -Fq '"wifi_firmware_upgrade" = "UPGRADE";' "$localizable_en" || fail "missing English WiFi upgrade localization"
grep -Fq '"wifi_dfu" = "WiFi DFU";' "$localizable_zh" || fail "missing Chinese WiFi DFU localization"
grep -Fq '"wifi_firmware_update" = "WiFi 固件更新";' "$localizable_zh" || fail "missing Chinese WiFi firmware title localization"
grep -Fq '"wifi_firmware_upgrade" = "升级";' "$localizable_zh" || fail "missing Chinese WiFi upgrade localization"

wifi_build_file_count=$(grep -Fc 'WiFiFirmwareUpdateViewController.swift in Sources */ = {isa = PBXBuildFile;' "$project")
[ "$wifi_build_file_count" -eq 4 ] || fail "WiFi firmware controller must have four PBXBuildFile entries"
wifi_sources_count=$(grep -Fc 'WiFiFirmwareUpdateViewController.swift in Sources */,' "$project")
[ "$wifi_sources_count" -eq 4 ] || fail "WiFi firmware controller must belong to all four target source phases"

rg -n 'UIImage\(named: "menu_wifi_dfu"\), title: "wifi_dfu"\.localizedString' "$gateway" >/dev/null || fail "WiFi DFU menu title must be localized"
rg -n 'let controller = WiFiFirmwareUpdateViewController\(\)' "$gateway" >/dev/null || fail "WiFi DFU menu must create the WiFi firmware controller"
rg -n 'navigationController\?\.pushViewController\(controller, animated: true\)' "$gateway" >/dev/null || fail "WiFi DFU menu must push the WiFi firmware controller"

echo "PASS: WiFi Gateway firmware update static checks"
