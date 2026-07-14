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
rg -n 'var currentVersionTitleText: String' "$parent" >/dev/null || fail "missing current version title hook"
rg -n 'var currentVersionDisplayText: String' "$parent" >/dev/null || fail "missing current version display hook"
rg -n 'var createsUIBeforeCloudRequest: Bool' "$parent" >/dev/null || fail "missing early UI hook"
rg -n 'var requiresAdditionalFirmwareReload: Bool' "$parent" >/dev/null || fail "missing additional reload state hook"
rg -n 'func loadAdditionalFirmwareData\(\)' "$parent" >/dev/null || fail "missing additional firmware load hook"
rg -n 'func refreshFirmwareUI\(\)' "$parent" >/dev/null || fail "missing firmware UI refresh hook"
rg -n 'var resetsServerFirmwareBeforeCloudRequest: Bool' "$parent" >/dev/null || fail "missing server firmware reset hook"
rg -n 'func isNewServerFirmwareAvailable\(_ serverData: FirmwareServerData\) -> Bool' "$parent" >/dev/null || fail "missing server firmware availability hook"
rg -n 'if resetsServerFirmwareBeforeCloudRequest' "$parent" >/dev/null || fail "firmware request ignores reset hook"
rg -n 'type\.serverData = nil' "$parent" >/dev/null || fail "firmware request does not clear stale server data"
rg -n 'noServerFirmware = false' "$parent" >/dev/null || fail "firmware request does not reset stale not-found state"
rg -n 'serverData\.version\.compare\(currentVersion, options: \.numeric\) == \.orderedDescending' "$parent" >/dev/null || fail "default availability must preserve numeric comparison"
rg -n 'func shouldShowServerFirmwareDetails\(_ serverData: FirmwareServerData\) -> Bool' "$parent" >/dev/null || fail "missing server firmware details visibility hook"
rg -n 'func isFirmwarePrimaryActionEnabled\(_ serverData: FirmwareServerData\) -> Bool' "$parent" >/dev/null || fail "missing firmware primary action enablement hook"
default_availability_count=$(grep -Fc 'return isNewServerFirmwareAvailable(serverData)' "$parent")
[ "$default_availability_count" -eq 2 ] || fail "default details and action hooks must preserve existing availability behavior"
rg -n 'if shouldShowServerFirmwareDetails\(newFirmwareData\)' "$parent" >/dev/null || fail "firmware details ignore visibility hook"
rg -n 'downloadBtn\.isEnabled = isFirmwarePrimaryActionEnabled\(newFirmwareData\)' "$parent" >/dev/null || fail "firmware button ignores enablement hook"
rg -n 'var showsFirmwareDeleteButton: Bool' "$parent" >/dev/null || fail "missing delete visibility hook"
rg -n 'var showsBetaImportAction: Bool' "$parent" >/dev/null || fail "missing beta import visibility hook"
rg -n 'var firmwarePrimaryActionTitle: String' "$parent" >/dev/null || fail "missing primary action title hook"
rg -n '@objc func firmwarePrimaryAction\(\)' "$parent" >/dev/null || fail "missing primary action hook"
rg -n 'customId: firmwareRequestCustomId' "$parent" >/dev/null || fail "latest request ignores customer id hook"
rg -n 'showsImportAction: showsBetaImportAction' "$parent" >/dev/null || fail "beta alert ignores import visibility hook"
rg -n 'title: firmwarePrimaryActionTitle' "$parent" >/dev/null || fail "button ignores title hook"
rg -n '#selector\(firmwarePrimaryAction\)' "$parent" >/dev/null || fail "button ignores action hook"
rg -n 'UILabel\(text: currentVersionTitleText' "$parent" >/dev/null || fail "current version title label ignores hook"
rg -n 'currentVersionLabel\.text = currentVersionDisplayText' "$parent" >/dev/null || fail "current version label ignores hook"
rg -n 'if createsUIBeforeCloudRequest' "$parent" >/dev/null || fail "viewDidLoad ignores early UI hook"
additional_load_count=$(grep -Fc 'loadAdditionalFirmwareData()' "$parent")
[ "$additional_load_count" -eq 3 ] || fail "additional firmware load must appear in declaration, initial load, and refresh"
rg -n 'if requiresAdditionalFirmwareReload' "$parent" >/dev/null || fail "firmware UI ignores additional failure"
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
if rg -n '0\.0\.1' "$wifi" >/dev/null; then
  fail "WiFi firmware controller must not contain a fixed target version"
fi
rg -n 'targetVersion: nil' "$wifi" >/dev/null || fail "WiFi firmware target version must start empty"
rg -n 'override var resetsServerFirmwareBeforeCloudRequest: Bool' "$wifi" >/dev/null || fail "WiFi firmware controller missing reset override"
rg -n 'import NordicSigMeshSDK' "$wifi" >/dev/null || fail "WiFi firmware page must import SDK"
rg -n 'private enum CurrentVersionState' "$wifi" >/dev/null || fail "missing current version state"
rg -n 'private let node: Node' "$wifi" >/dev/null || fail "WiFi firmware page missing target node"
rg -n 'private var currentVersionRequestID: Int = 0' "$wifi" >/dev/null || fail "missing stale callback guard"
rg -n 'init\(node: Node\)' "$wifi" >/dev/null || fail "WiFi firmware page initializer must require node"
rg -n 'override var currentVersionTitleText: String' "$wifi" >/dev/null || fail "WiFi page missing Current version title"
rg -n 'override var currentVersionDisplayText: String' "$wifi" >/dev/null || fail "WiFi page missing current version display state"
rg -n 'override var createsUIBeforeCloudRequest: Bool' "$wifi" >/dev/null || fail "WiFi page must create UI before requests complete"
rg -n 'override var requiresAdditionalFirmwareReload: Bool' "$wifi" >/dev/null || fail "WiFi page missing device failure refresh state"
rg -n 'override func loadAdditionalFirmwareData\(\)' "$wifi" >/dev/null || fail "WiFi page missing firmware version query"
rg -n 'SunricherVendorGet\(function: \.wifiGatewayFirmwareVersion\)' "$wifi" >/dev/null || fail "WiFi page does not send 43 14"
rg -n 'timeout: 10' "$wifi" >/dev/null || fail "WiFi firmware query must use 10-second Mesh timeout"
rg -n 'currentVersionRequestID == requestID' "$wifi" >/dev/null || fail "WiFi page does not reject stale callbacks"
rg -n 'case \.wifiGatewayFirmwareVersion\(\.success\(let version\)\)' "$wifi" >/dev/null || fail "WiFi page does not consume typed version result"
rg -n 'compare\(currentVersion, options: \.numeric\) == \.orderedDescending' "$wifi" >/dev/null || fail "WiFi page missing numeric version comparison"
rg -n 'override func shouldShowServerFirmwareDetails\(_ serverData: FirmwareServerData\) -> Bool' "$wifi" >/dev/null || fail "WiFi page missing failed-current-version details override"
rg -n 'if case \.failed = currentVersionState' "$wifi" >/dev/null || fail "WiFi details override does not detect failed current version"
rg -n 'return isNewServerFirmwareAvailable\(serverData\)' "$wifi" >/dev/null || fail "WiFi non-failed details must preserve strict comparison"
if rg -n 'override func isFirmwarePrimaryActionEnabled' "$wifi" >/dev/null; then
  fail "WiFi page must not bypass strict primary action enablement"
fi
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
grep -Fq '"current_version" = "Current version";' "$localizable_en" || fail "missing English Current version localization"
grep -Fq '"wifi_dfu" = "WiFi DFU";' "$localizable_zh" || fail "missing Chinese WiFi DFU localization"
grep -Fq '"wifi_firmware_update" = "WiFi 固件更新";' "$localizable_zh" || fail "missing Chinese WiFi firmware title localization"
grep -Fq '"wifi_firmware_upgrade" = "升级";' "$localizable_zh" || fail "missing Chinese WiFi upgrade localization"
grep -Fq '"current_version" = "当前版本";' "$localizable_zh" || fail "missing Chinese Current version localization"

wifi_build_file_count=$(grep -Fc 'WiFiFirmwareUpdateViewController.swift in Sources */ = {isa = PBXBuildFile;' "$project")
[ "$wifi_build_file_count" -eq 4 ] || fail "WiFi firmware controller must have four PBXBuildFile entries"
wifi_sources_count=$(grep -Fc 'WiFiFirmwareUpdateViewController.swift in Sources */,' "$project")
[ "$wifi_sources_count" -eq 4 ] || fail "WiFi firmware controller must belong to all four target source phases"

rg -n 'UIImage\(named: "menu_wifi_dfu"\), title: "wifi_dfu"\.localizedString' "$gateway" >/dev/null || fail "WiFi DFU menu title must be localized"
rg -n 'let controller = WiFiFirmwareUpdateViewController\(node: self\.node\)' "$gateway" >/dev/null || fail "WiFi DFU menu must pass current node"
rg -n 'navigationController\?\.pushViewController\(controller, animated: true\)' "$gateway" >/dev/null || fail "WiFi DFU menu must push the WiFi firmware controller"

echo "PASS: WiFi Gateway firmware update static checks"
