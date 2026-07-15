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
builder="SunSmart/Main/Firmware/Model/WiFiFirmwareDFUMetadataBuilder.swift"
state="SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift"
coordinator="SunSmart/Main/Firmware/Controller/WiFiFirmwareDFUCoordinator.swift"
updating_view="SunSmart/Main/Firmware/View/WiFiFirmwareUpdatingView.swift"
gateway="SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift"
project="SunSmart.xcodeproj/project.pbxproj"
localizable_en="SunSmart/en.lproj/Localizable.strings"
localizable_zh="SunSmart/zh-Hans.lproj/Localizable.strings"

[ -f "$builder" ] || fail "missing WiFi firmware DFU metadata builder"
[ -f "$state" ] || fail "missing WiFi firmware DFU state model"
rg -n 'UserData\.currentServerRegion\.baseURL' "$builder" >/dev/null || fail "URL builder must use current app region"
rg -n 'components\.scheme = "http"' "$builder" >/dev/null || fail "URL builder must force HTTP"
rg -n '/sitespace/ota/download' "$builder" >/dev/null || fail "URL builder missing OTA download path"
rg -n 'URLQueryItem\(name: "key", value: filename\)' "$builder" >/dev/null || fail "URL builder must encode filename as key query"
rg -n 'enum WiFiFirmwareUpdatingKind' "$state" >/dev/null || fail "missing WiFi firmware UI state"
rg -n 'struct WiFiFirmwareDFUSession' "$state" >/dev/null || fail "missing WiFi firmware persisted session"
[ -f "$coordinator" ] || fail "missing WiFi firmware DFU coordinator"
rg -n 'WiFiGatewayDFUMetadata\(url: url, firmwareID: firmwareID\)' "$coordinator" >/dev/null || fail "coordinator must use new SDK metadata"
rg -n 'addGlobalMessageObserver' "$coordinator" >/dev/null || fail "coordinator missing unsolicited status observer"
rg -n 'removeGlobalMessageObserver' "$coordinator" >/dev/null || fail "coordinator must remove unsolicited status observer"
rg -n 'guard self\.isActive, !self\.requestInFlight' "$coordinator" >/dev/null || fail "observer must not race the active request callback"
rg -n 'timeout: 5' "$coordinator" >/dev/null || fail "DFU status query timeout must be 5 seconds"
rg -n 'after: 2' "$coordinator" >/dev/null || fail "DFU active poll interval must be 2 seconds"
rg -n 'after: 10' "$coordinator" >/dev/null || fail "DFU degraded poll interval must be 10 seconds"
rg -n 'private var generation = 0' "$coordinator" >/dev/null || fail "coordinator missing stale callback generation"
rg -n 'WiFiFirmwareDFUSessionStore' "$coordinator" >/dev/null || fail "coordinator missing persisted session store"
rg -n 'hadAcceptedSession' "$coordinator" >/dev/null || fail "coordinator must retain accepted session during restore"
rg -n 'status == nil, hadAcceptedSession' "$coordinator" >/dev/null || fail "restore timeout must keep polling accepted session"
rg -n 'emit\(\.updateState\(initialState\)\)' "$coordinator" >/dev/null || fail "accepted start must expose an initial DFU state"
[ -f "$updating_view" ] || fail "missing WiFi firmware updating view"
rg -n 'func configure\(state: WiFiFirmwareUpdatingState\)' "$updating_view" >/dev/null || fail "updating view missing state renderer"
rg -n 'alert_failed' "$updating_view" >/dev/null || fail "updating view missing failure asset"
rg -n 'sync_success_small' "$updating_view" >/dev/null || fail "updating view missing success asset"
if rg -n 'SCRX|SCRY' "$updating_view" >/dev/null; then
  fail "updating view must use fixed point layout"
fi
for key in wifi_firmware_upgrade_again wifi_firmware_connection_failed wifi_firmware_communication_timeout wifi_firmware_server_unable wifi_firmware_downloading wifi_firmware_updating wifi_firmware_download_failed wifi_firmware_upgrade_failed wifi_firmware_upgrade_complete; do
  grep -Fq "\"$key\" =" "$localizable_en" || fail "missing English $key localization"
  grep -Fq "\"$key\" =" "$localizable_zh" || fail "missing Chinese $key localization"
done

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
rg -n 'var usesScrollableFirmwareContent: Bool \{ false \}' "$parent" >/dev/null || fail "missing scrollable firmware content hook"
rg -n 'func makeAdditionalFirmwareContentView\(\) -> UIView\?' "$parent" >/dev/null || fail "missing additional firmware content view hook"
rg -n 'var additionalFirmwareContentTopSpacing: CGFloat \{ 0 \}' "$parent" >/dev/null || fail "missing additional content spacing hook"
rg -n 'var additionalFirmwareContentHorizontalInset: CGFloat \{ 0 \}' "$parent" >/dev/null || fail "missing additional content inset hook"
rg -n 'func setAdditionalFirmwareContentHidden\(_ hidden: Bool\)' "$parent" >/dev/null || fail "missing additional content visibility hook"
rg -n 'func updateFirmwarePrimaryAction\(titleKey: String, isEnabled: Bool\)' "$parent" >/dev/null || fail "missing dynamic primary action hook"
rg -n 'func applyAdditionalFirmwareUIState\(\)' "$parent" >/dev/null || fail "missing additional firmware UI state hook"
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
rg -n 'init\(node: Node\)' "$wifi" >/dev/null || fail "WiFi firmware page initializer must require node"
rg -n 'override var currentVersionTitleText: String' "$wifi" >/dev/null || fail "WiFi page missing Current version title"
rg -n 'override var currentVersionDisplayText: String' "$wifi" >/dev/null || fail "WiFi page missing current version display state"
rg -n 'override var createsUIBeforeCloudRequest: Bool' "$wifi" >/dev/null || fail "WiFi page must create UI before requests complete"
rg -n 'override var requiresAdditionalFirmwareReload: Bool' "$wifi" >/dev/null || fail "WiFi page missing device failure refresh state"
rg -n 'override func loadAdditionalFirmwareData\(\)' "$wifi" >/dev/null || fail "WiFi page missing firmware version query"
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
if rg -n 'under_development' "$wifi" >/dev/null; then
  fail "WiFi upgrade placeholder must be removed"
fi
rg -n 'WiFiFirmwareDFUCoordinator\(node: node\)' "$wifi" >/dev/null || fail "WiFi page missing DFU coordinator"
rg -n 'dfuCoordinator\.start\(filename: serverData\.filename, version: serverData\.version\)' "$wifi" >/dev/null || fail "WiFi page must start DFU with server filename and version"
rg -n 'dfuCoordinator\.consumeSuccess\(\)' "$wifi" >/dev/null || fail "DONE must consume successful session"
rg -n 'case \.cancelDisabled' "$wifi" >/dev/null || fail "WiFi page missing disabled CANCEL action"
rg -n '"wifi_firmware_upgrade_again"' "$wifi" >/dev/null || fail "WiFi page missing UPGRADE AGAIN action"
rg -n 'override var usesScrollableFirmwareContent: Bool' "$wifi" >/dev/null || fail "WiFi page must enable scrollable content"
rg -n 'override var additionalFirmwareContentTopSpacing: CGFloat \{ 32 \}' "$wifi" >/dev/null || fail "WiFi status top spacing must be 32 points"
rg -n 'override var additionalFirmwareContentHorizontalInset: CGFloat \{ 36 \}' "$wifi" >/dev/null || fail "WiFi status horizontal inset must be 36 points"
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
