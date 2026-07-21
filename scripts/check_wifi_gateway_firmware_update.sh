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
reducer="SunSmart/Main/Firmware/Model/WiFiFirmwareDFUStatusReducer.swift"
cancel_reducer="SunSmart/Main/Firmware/Model/WiFiFirmwareDFUCancelReducer.swift"
transaction_gate="SunSmart/Main/Firmware/Model/WiFiFirmwareDFUTransactionGate.swift"
timing="SunSmart/Main/Device/Gateway/Model/WiFiGatewayV19Timing.swift"
coordinator="SunSmart/Main/Firmware/Controller/WiFiFirmwareDFUCoordinator.swift"
updating_view="SunSmart/Main/Firmware/View/WiFiFirmwareUpdatingView.swift"
gateway="SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift"
project="SunSmart.xcodeproj/project.pbxproj"
localizable_en="SunSmart/en.lproj/Localizable.strings"
localizable_zh="SunSmart/zh-Hans.lproj/Localizable.strings"
focused_test="Tests/Firmware/WiFiFirmwareDFUStatusReducerTests.swift"
cancel_focused_test="Tests/Firmware/WiFiFirmwareDFUCancelReducerTests.swift"
transaction_gate_test="Tests/Firmware/WiFiFirmwareDFUTransactionGateTests.swift"
cancel_protocol_contract="Tests/Firmware/WiFiGatewayDFUCancelV19Contract.swift"
builder_test="Tests/Firmware/WiFiFirmwareDFUMetadataBuilderTests.swift"
sdk_source="/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK"
sdk_text_validator="$sdk_source/MeshLib/Message/Vendor/WiFiGatewayV19TextValidator.swift"
sdk_status="$sdk_source/MeshLib/Message/Vendor/WiFiGatewayDFUStatus.swift"
sdk_contract="/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/scripts/check_wifi_gateway_dfu_status_v19.swift"
sdk_start="$sdk_source/MeshLib/Message/Vendor/WiFiGatewayDFUStart.swift"
sdk_cancel="$sdk_source/MeshLib/Message/Vendor/WiFiGatewayDFUCancel.swift"
sdk_start_contract="/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/scripts/check_wifi_gateway_dfu_start_v19.swift"

[ -f "$builder" ] || fail "missing WiFi firmware DFU metadata builder"
[ -f "$state" ] || fail "missing WiFi firmware DFU state model"
rg -n 'UserData\.currentServerRegion\.baseURL' "$builder" >/dev/null || fail "URL builder must use current app region"
rg -n 'components\.scheme = "http"' "$builder" >/dev/null || fail "URL builder must force HTTP"
rg -n '/sitespace/ota/download' "$builder" >/dev/null || fail "URL builder missing OTA download path"
rg -n 'URLQueryItem\(name: "key", value: filename\)' "$builder" >/dev/null || fail "URL builder must encode filename as key query"
rg -n 'enum WiFiFirmwareUpdatingKind' "$state" >/dev/null || fail "missing WiFi firmware UI state"
rg -n 'struct WiFiFirmwareDFUSession' "$state" >/dev/null || fail "missing WiFi firmware persisted session"
[ -f "$reducer" ] || fail "missing WiFi OTA V1.9 reducer"
[ -f "$cancel_reducer" ] || fail "missing WiFi OTA cancel reducer"
[ -f "$sdk_cancel" ] || fail "missing SDK WiFi OTA cancel protocol"
rg -n 'responseTimeout: TimeInterval = 7' "$cancel_reducer" >/dev/null || fail "cancel RET timeout must be 7 seconds"
rg -n 'statusTimeout: TimeInterval = 3' "$cancel_reducer" >/dev/null || fail "cancel recovery GET timeout must be 3 seconds"
rg -n 'maximumRecoveryQueries = 3' "$cancel_reducer" >/dev/null || fail "cancel recovery must stop after three GETs"
rg -n 'unknownQueryInterval: TimeInterval = 30' "$cancel_reducer" >/dev/null || fail "unknown cancellation query interval must be 30 seconds"
rg -n 'statusTimeout: TimeInterval = 3' "$reducer" >/dev/null || fail "status GET timeout must be 3 seconds"
rg -n 'quietQueryInterval: TimeInterval = 10' "$reducer" >/dev/null || fail "quiet query interval must be 10 seconds"
rg -n 'unknownThreshold: TimeInterval = 30' "$reducer" >/dev/null || fail "unknown threshold must be 30 seconds"
rg -n 'unknownQueryInterval: TimeInterval = 30' "$reducer" >/dev/null || fail "unknown query interval must be 30 seconds"
rg -n 'case cancelled' "$state" >/dev/null || fail "state missing cancelled terminal"
rg -n 'case communicationUnknown' "$state" >/dev/null || fail "state missing communication unknown"
[ -f "$coordinator" ] || fail "missing WiFi firmware DFU coordinator"
rg -n 'UInt64\.random\(in: 1\.\.\.UInt64\.max\)' "$coordinator" >/dev/null || fail "each explicit start must create a nonzero random OTA ID"
rg -n 'WiFiGatewayDFUStartRequest\(' "$coordinator" >/dev/null || fail "coordinator must use the V1.9 start request"
rg -n 'startResponse\.otaID == otaID' "$coordinator" >/dev/null || fail "coordinator must match the V1.9 RET OTA ID"
rg -n 'queryPendingStartStatusOnce' "$coordinator" >/dev/null || fail "coordinator missing one-shot start recovery query"
rg -n 'nextAfterMissingRET' "$coordinator" "$reducer" >/dev/null || fail "coordinator missing EVENT/query start recovery decision"
start_send_count=$(grep -Fc 'SunricherVendorSet(function: .wifiGatewayDFUStart(request))' "$coordinator")
[ "$start_send_count" -eq 1 ] || fail "coordinator must send the V1.9 start request exactly once"
if rg -n 'WiFiGatewayDFUMetadata|sha256' "$coordinator" "$sdk_start" >/dev/null ||
   rg -n 'size|sha256' "$sdk_start" >/dev/null; then
  fail "V1.9 start must not use legacy metadata, size, or sha256"
fi
rg -n 'addGlobalMessageObserver' "$coordinator" >/dev/null || fail "coordinator missing unsolicited status observer"
rg -n 'removeGlobalMessageObserver' "$coordinator" >/dev/null || fail "coordinator must remove unsolicited status observer"
rg -n 'addGlobalConnectionObserver' "$coordinator" >/dev/null || fail "coordinator missing connection observer"
rg -n 'removeGlobalConnectionObserver' "$coordinator" >/dev/null || fail "coordinator must remove connection observer"
rg -n 'case \.wifiGatewayDFUStatus' "$coordinator" >/dev/null || fail "coordinator missing OTA EVENT route"
rg -n 'requiresAuthoritativeQuery' "$coordinator" >/dev/null || fail "coordinator missing authoritative reconnect gate"
dfu_status_timeout_count=$(grep -Fc 'timeout: WiFiGatewayV19Timing.responseTimeout(for: .dfuStatus)' "$coordinator" || true)
[ "$dfu_status_timeout_count" -eq 2 ] || fail "all 0x11 requests must use the V1.9 status deadline"
rg -n 'timeout: WiFiGatewayV19Timing\.responseTimeout\(for: \.dfuStart\)' "$coordinator" >/dev/null || fail "0x10 must use the V1.9 3-second deadline"
rg -n 'timeout: WiFiGatewayV19Timing\.responseTimeout\(for: \.firmwareVersion\)' "$coordinator" >/dev/null || fail "0x14 must use the V1.9 7-second deadline"
rg -n 'timeout: WiFiGatewayV19Timing\.responseTimeout\(for: \.dfuCancel\)' "$coordinator" >/dev/null || fail "0x15 must use the shared V1.9 deadline"
rg -n 'private var generation = 0' "$coordinator" >/dev/null || fail "coordinator missing stale callback generation"
rg -n 'WiFiFirmwareDFUSessionStore' "$coordinator" >/dev/null || fail "coordinator missing persisted session store"
rg -n 'prepareForPageRecovery\(\)' "$state" >/dev/null || fail "session missing page recovery policy"
rg -n 'isStatusQueryEligible' "$state" >/dev/null || fail "session missing status query eligibility"
rg -n 'restored\.prepareForPageRecovery\(\)' "$coordinator" >/dev/null || fail "restored session must require authoritative status"
authoritative_refresh_line=$(grep -n 'if session\.requiresAuthoritativeQuery' "$coordinator" | head -1 | cut -d: -f1)
terminal_replay_line=$(grep -n 'if session\.lastStatus?\.stage\.isTerminal == true' "$coordinator" | head -1 | cut -d: -f1)
[ -n "$authoritative_refresh_line" ] || fail "refresh missing authoritative recovery branch"
[ -n "$terminal_replay_line" ] || fail "refresh missing in-memory terminal replay branch"
[ "$authoritative_refresh_line" -lt "$terminal_replay_line" ] || fail "authoritative recovery must run before terminal replay"
rg -n 'session\.isStatusQueryEligible' "$coordinator" >/dev/null || fail "coordinator query scheduling ignores restored terminal eligibility"
if rg -n 'isActiveNonterminalSession' "$coordinator" >/dev/null; then
  fail "coordinator must not exclude authoritative terminal recovery"
fi
rg -n 'WiFiFirmwareDFUAuthoritativeRecoveryPolicy\.decision' "$coordinator" >/dev/null || fail "coordinator missing authoritative response policy"
rg -n 'case \.clearStaleTerminal:' "$coordinator" >/dev/null || fail "coordinator missing stale terminal cleanup"
rg -n 'func beginInitialLoad\(\)' "$coordinator" >/dev/null || fail "coordinator missing current-version preflight entry"
rg -n 'func refreshOTAStatus\(\)' "$coordinator" >/dev/null || fail "coordinator missing gated OTA status entry"
begin_initial_line=$(grep -n '^    func beginInitialLoad()' "$coordinator" | cut -d: -f1)
deactivate_line=$(grep -n '^    func deactivate()' "$coordinator" | cut -d: -f1)
initial_observer_line=$(awk -v start="$begin_initial_line" -v end="$deactivate_line" 'NR > start && NR < end && /registerObserversIfNeeded\(\)/ { print NR; exit }' "$coordinator")
initial_status_line=$(awk -v start="$begin_initial_line" -v end="$deactivate_line" 'NR > start && NR < end && /queryDFUStatus\(purpose: \.normal\(authoritative: true\)\)/ { print NR; exit }' "$coordinator")
[ -n "$initial_observer_line" ] || fail "initial load must register observers immediately"
[ -n "$initial_status_line" ] || fail "initial load must issue an authoritative 0x11 query"
[ "$initial_observer_line" -lt "$initial_status_line" ] || fail "initial observers must be registered before authoritative 0x11"
if awk -v start="$begin_initial_line" -v end="$deactivate_line" 'NR > start && NR < end && /queryCurrentVersion\(\)/ { found = 1 } END { exit !found }' "$coordinator"; then
  fail "initial load must not query 0x14 before authoritative 0x11"
fi
rg -n 'scheduleCurrentVersionAfterAuthoritativeStatus' "$coordinator" >/dev/null || fail "authoritative 0x11 must decide when 0x14 may run"
rg -n 'func cancel\(\)' "$coordinator" >/dev/null || fail "coordinator missing single-send cancel entry"
rg -n 'SunricherVendorSet\(function: \.wifiGatewayDFUCancel\(request\)\)' "$coordinator" >/dev/null || fail "coordinator must send 0x43/0x15"
rg -n 'case \.wifiGatewayDFUCancel' "$coordinator" >/dev/null || fail "coordinator missing global cancel RET route"
rg -n 'WiFiFirmwareDFUStatusSource\.cancellation|source: \.cancellation' "$coordinator" >/dev/null || fail "matched cancelled status must use cancellation source"
rg -n 'cancelState\.blocksNewStart' "$coordinator" >/dev/null || fail "start must remain blocked while cancellation is unresolved"
rg -n 'func canStartNewOTA' "$coordinator" >/dev/null || fail "coordinator missing unified Start availability truth"
rg -n 'transactionGate\.blocksStart' "$coordinator" >/dev/null || fail "Start truth must read the persistent transaction gate"
rg -n 'guard canStartNewOTA\(\)' "$coordinator" >/dev/null || fail "start() must use the unified Start truth"
rg -n 'case startAvailability\(Bool\)' "$coordinator" >/dev/null || fail "coordinator missing Start availability event"
rg -n 'private var cancelGateWorkItem: DispatchWorkItem\?' "$coordinator" >/dev/null || fail "coordinator missing independent cancel gate deadline work item"
rg -n 'session\.transactionGate\.beginCancel' "$coordinator" >/dev/null || fail "cancel must create a transaction gate before sending"
rg -n 'session\.transactionGate\.finishCancel\(\)' "$coordinator" >/dev/null || fail "cancel callback must release its transaction gate"
finish_cancel_count=$(grep -Fc 'transactionGate.finishCancel()' "$coordinator" || true)
[ "$finish_cancel_count" -eq 1 ] || fail "only the transport callback helper may finish the cancel gate"
cancel_callback_gate_line=$(grep -n 'self\.finishCancelTransaction()' "$coordinator" | head -1 | cut -d: -f1 || true)
cancel_callback_business_line=$(grep -n 'self\.handleCancelCallback(response, expectedOTAID: otaID)' "$coordinator" | head -1 | cut -d: -f1)
[ -n "$cancel_callback_gate_line" ] || fail "cancel callback must finish the transaction gate"
[ "$cancel_callback_gate_line" -lt "$cancel_callback_business_line" ] || fail "cancel callback must finish the gate before interpreting business response"
if rg -n 'cancelRequestInFlight' "$coordinator" >/dev/null; then
  fail "cancelRequestInFlight must not replace the persistent transaction gate"
fi
rg -n 'WiFiFirmwareDFUCancelTiming\.unknownQueryInterval' "$coordinator" >/dev/null || fail "unknown cancellation must use 30-second scheduling"
cancel_send_count=$(grep -Fc 'SunricherVendorSet(function: .wifiGatewayDFUCancel(request))' "$coordinator")
[ "$cancel_send_count" -eq 1 ] || fail "coordinator must send cancel exactly once"
cancel_function_line=$(grep -n '^    func cancel()' "$coordinator" | cut -d: -f1)
cancel_save_line=$(awk -v start="$cancel_function_line" 'NR > start && /saveSession\(\)/ { print NR; exit }' "$coordinator")
cancel_send_line=$(grep -n 'SunricherVendorSet(function: .wifiGatewayDFUCancel(request))' "$coordinator" | cut -d: -f1)
[ -n "$cancel_save_line" ] || fail "cancel state must be persisted before send"
[ "$cancel_function_line" -lt "$cancel_save_line" ] || fail "cancel persistence must be inside cancel entry"
[ "$cancel_save_line" -lt "$cancel_send_line" ] || fail "cancel state must be persisted before 0x43/0x15 send"
if rg -n 'CANCEL AGAIN|cancel_again' SunSmart >/dev/null; then
  fail "cancel must not expose a retry action"
fi
[ -f "$updating_view" ] || fail "missing WiFi firmware updating view"
rg -n 'func configure\(state: WiFiFirmwareUpdatingState\)' "$updating_view" >/dev/null || fail "updating view missing state renderer"
rg -n 'alert_failed' "$updating_view" >/dev/null || fail "updating view missing failure asset"
rg -n 'sync_success_small' "$updating_view" >/dev/null || fail "updating view missing success asset"
rg -n 'case \.cancelled:' "$updating_view" >/dev/null || fail "updating view missing cancelled renderer"
rg -n 'titleKey = "wifi_firmware_upgrade_cancelled"' "$updating_view" >/dev/null || fail "cancelled renderer missing localized title"
rg -n 'case \.communicationUnknown:' "$updating_view" >/dev/null || fail "updating view missing communication-unknown renderer"
rg -n 'case \.cancellationUnknown:' "$updating_view" >/dev/null || fail "updating view missing cancellation-unknown renderer"
rg -n 'titleKey = "wifi_firmware_cancel_result_unknown"' "$updating_view" >/dev/null || fail "cancellation-unknown title is missing"
rg -n 'detailKey = "wifi_firmware_waiting_status_confirmation"' "$updating_view" >/dev/null || fail "cancellation-unknown detail is missing"
rg -n -U 'detailLabel\.bottomAnchor\.constraint\(lessThanOrEqualTo: bottomAnchor\)\s+\.withPriority\(\.defaultHigh\)' "$updating_view" >/dev/null || fail "hidden WiFi OTA view must allow its bottom constraint to yield"
if rg -n 'SCRX|SCRY' "$updating_view" >/dev/null; then
  fail "updating view must use fixed point layout"
fi
for key in wifi_firmware_upgrade_again wifi_firmware_connection_failed wifi_firmware_communication_timeout wifi_firmware_server_unable wifi_firmware_downloading wifi_firmware_updating wifi_firmware_download_failed wifi_firmware_upgrade_failed wifi_firmware_upgrade_complete wifi_firmware_upgrade_cancelled wifi_firmware_cancel_not_effective wifi_firmware_cancel_result_unknown wifi_firmware_waiting_status_confirmation; do
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
rg -n 'func loadFirmwareData\(\)' "$parent" >/dev/null || fail "missing firmware load-cycle hook"
rg -n 'func loadCloudFirmwareRequest\(completion: \(\(\) -> Void\)\? = nil\)' "$parent" >/dev/null || fail "cloud firmware request missing completion"
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
[ "$additional_load_count" -eq 2 ] || fail "additional firmware load must appear in its declaration and default load cycle"
firmware_load_count=$(grep -Fc 'loadFirmwareData()' "$parent")
[ "$firmware_load_count" -eq 3 ] || fail "firmware load cycle must appear in its declaration, initial load, and refresh"
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
rg -n 'override func loadFirmwareData\(\)' "$wifi" >/dev/null || fail "WiFi page missing gated firmware load cycle"
rg -n 'dfuCoordinator\.beginInitialLoad\(\)' "$wifi" >/dev/null || fail "WiFi page must start authoritative OTA recovery"
if rg -n 'WiFiFirmwareInitialLoadGate|completeInitialLoadRequirement|dfuCoordinator\.refreshOTAStatus\(\)' "$wifi" >/dev/null; then
  fail "cloud/current-version gate must not control OTA recovery"
fi
page_begin_line=$(grep -n 'dfuCoordinator\.beginInitialLoad()' "$wifi" | head -1 | cut -d: -f1)
page_cloud_line=$(grep -n 'loadCloudFirmwareRequest' "$wifi" | head -1 | cut -d: -f1)
[ "$page_begin_line" -lt "$page_cloud_line" ] || fail "authoritative OTA recovery must start before the cloud request"
rg -n 'compare\(currentVersion, options: \.numeric\) != \.orderedAscending' "$wifi" >/dev/null || fail "WiFi page must preserve same-version upgrade testing behavior"
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
rg -n 'case \.cancel:' "$wifi" >/dev/null || fail "WiFi page missing enabled CANCEL action"
rg -n 'dfuCoordinator\.cancel\(\)' "$wifi" >/dev/null || fail "CANCEL must call the coordinator immediately"
rg -n 'case \.cancelAvailability\(let enabled\)' "$wifi" >/dev/null || fail "WiFi page must consume cancel availability"
rg -n 'case \.startAvailability\(let enabled\)' "$wifi" >/dev/null || fail "WiFi page must consume unified Start availability"
rg -n 'private var canStartOTA = false' "$wifi" >/dev/null || fail "WiFi page missing Start gate state"
can_start_usage_count=$(grep -Fc 'canStartOTA' "$wifi" || true)
[ "$can_start_usage_count" -ge 4 ] || fail "Upgrade and Retry enablement must both use the unified Start gate"
rg -n '"wifi_firmware_upgrade_again"' "$wifi" >/dev/null || fail "WiFi page missing UPGRADE AGAIN action"
rg -n 'case \.downloading:' "$wifi" >/dev/null || fail "WiFi page missing cancellable downloading state"
rg -n 'case \.updating, \.communicationUnknown, \.cancellationUnknown:' "$wifi" >/dev/null || fail "WiFi page must keep CANCEL disabled outside cancellable stages"
rg -n 'case \.cancelled:' "$wifi" >/dev/null || fail "WiFi page missing cancelled primary action"
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
grep -Fq '"wifi_firmware_cancel_not_effective" = "Unable to cancel. The update will continue.";' "$localizable_en" || fail "incorrect English cancel failure localization"
grep -Fq '"wifi_firmware_cancel_result_unknown" = "Cancellation result unknown";' "$localizable_en" || fail "incorrect English cancel unknown localization"
grep -Fq '"wifi_firmware_waiting_status_confirmation" = "Waiting for status confirmation";' "$localizable_en" || fail "incorrect English cancel waiting localization"
grep -Fq '"wifi_firmware_cancel_not_effective" = "无法取消，固件升级将继续。";' "$localizable_zh" || fail "incorrect Chinese cancel failure localization"
grep -Fq '"wifi_firmware_cancel_result_unknown" = "取消结果未知";' "$localizable_zh" || fail "incorrect Chinese cancel unknown localization"
grep -Fq '"wifi_firmware_waiting_status_confirmation" = "正在等待状态确认";' "$localizable_zh" || fail "incorrect Chinese cancel waiting localization"

wifi_build_file_count=$(grep -F 'WiFiFirmwareUpdateViewController.swift in Sources */ = {isa = PBXBuildFile;' "$project" | awk '{print $1}' | sort -u | wc -l | tr -d ' ')
[ "$wifi_build_file_count" -eq 4 ] || fail "WiFi firmware controller must have four PBXBuildFile entries"
wifi_sources_count=$(grep -Fc 'WiFiFirmwareUpdateViewController.swift in Sources */,' "$project")
[ "$wifi_sources_count" -eq 4 ] || fail "WiFi firmware controller must belong to all four target source phases"
reducer_build_file_count=$(grep -F 'WiFiFirmwareDFUStatusReducer.swift in Sources */ = {isa = PBXBuildFile;' "$project" | awk '{print $1}' | sort -u | wc -l | tr -d ' ')
[ "$reducer_build_file_count" -eq 4 ] || fail "WiFi OTA reducer must have four PBXBuildFile entries"
reducer_sources_count=$(grep -Fc 'WiFiFirmwareDFUStatusReducer.swift in Sources */,' "$project")
[ "$reducer_sources_count" -eq 4 ] || fail "WiFi OTA reducer must belong to all four target source phases"
cancel_reducer_build_file_count=$(grep -F 'WiFiFirmwareDFUCancelReducer.swift in Sources */ = {isa = PBXBuildFile;' "$project" | awk '{print $1}' | sort -u | wc -l | tr -d ' ')
[ "$cancel_reducer_build_file_count" -eq 4 ] || fail "WiFi OTA cancel reducer must have four PBXBuildFile entries"
cancel_reducer_sources_count=$(grep -Fc 'WiFiFirmwareDFUCancelReducer.swift in Sources */,' "$project")
[ "$cancel_reducer_sources_count" -eq 4 ] || fail "WiFi OTA cancel reducer must belong to all four target source phases"

rg -n 'UIImage\(named: "menu_wifi_dfu"\), title: "wifi_dfu"\.localizedString' "$gateway" >/dev/null || fail "WiFi DFU menu title must be localized"
rg -n 'let controller = WiFiFirmwareUpdateViewController\(node: self\.node\)' "$gateway" >/dev/null || fail "WiFi DFU menu must pass current node"
rg -n 'navigationController\?\.pushViewController\(controller, animated: true\)' "$gateway" >/dev/null || fail "WiFi DFU menu must push the WiFi firmware controller"

[ -f "$focused_test" ] || fail "missing WiFi OTA reducer focused test"
swiftc -parse-as-library "$transaction_gate" "$cancel_reducer" "$reducer" "$state" "$focused_test" -o /tmp/WiFiFirmwareDFUStatusReducerTests
/tmp/WiFiFirmwareDFUStatusReducerTests

[ -f "$cancel_focused_test" ] || fail "missing WiFi OTA cancel reducer focused test"
swiftc -parse-as-library "$transaction_gate" "$cancel_reducer" "$reducer" "$state" "$cancel_focused_test" -o /tmp/WiFiFirmwareDFUCancelReducerTests
/tmp/WiFiFirmwareDFUCancelReducerTests

[ -f "$transaction_gate_test" ] || fail "missing WiFi OTA transaction gate focused test"
swiftc -parse-as-library "$transaction_gate" "$transaction_gate_test" -o /tmp/WiFiFirmwareDFUTransactionGateTests
/tmp/WiFiFirmwareDFUTransactionGateTests

[ -f "$cancel_protocol_contract" ] || fail "missing WiFi OTA cancel protocol contract"
swiftc -parse-as-library "$sdk_cancel" "$cancel_protocol_contract" -o /tmp/WiFiGatewayDFUCancelV19Contract
/tmp/WiFiGatewayDFUCancelV19Contract

[ -f "$builder_test" ] || fail "missing WiFi OTA URL builder focused test"
swiftc -parse-as-library "$builder" "$builder_test" -o /tmp/WiFiFirmwareDFUMetadataBuilderTests
/tmp/WiFiFirmwareDFUMetadataBuilderTests

[ -f "$sdk_status" ] || fail "missing SDK WiFi OTA V1.9 status parser"
[ -f "$sdk_contract" ] || fail "missing SDK WiFi OTA V1.9 parser contract"
swiftc -parse-as-library "$sdk_text_validator" "$sdk_status" "$sdk_contract" -o /tmp/WiFiGatewayDFUStatusV19Contract
/tmp/WiFiGatewayDFUStatusV19Contract

[ -f "$sdk_start" ] || fail "missing SDK WiFi OTA V1.9 start model"
[ -f "$sdk_start_contract" ] || fail "missing SDK WiFi OTA V1.9 start contract"
swiftc -parse-as-library "$sdk_text_validator" "$sdk_start" "$sdk_start_contract" -o /tmp/WiFiGatewayDFUStartV19Contract
/tmp/WiFiGatewayDFUStartV19Contract

echo "PASS: WiFi Gateway firmware update static checks"
