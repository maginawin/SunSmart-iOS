#!/usr/bin/env bash
set -euo pipefail

assert_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"

  if ! grep -q "$pattern" "$file"; then
    echo "FAIL: $message" >&2
    echo "  expected pattern: $pattern" >&2
    echo "  in file: $file" >&2
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"

  if grep -q "$pattern" "$file"; then
    echo "FAIL: $message" >&2
    echo "  unexpected pattern: $pattern" >&2
    echo "  in file: $file" >&2
    exit 1
  fi
}

assert_count() {
  local file="$1"
  local pattern="$2"
  local expected_count="$3"
  local message="$4"

  local actual_count
  actual_count=$(grep -c "$pattern" "$file" || true)
  if [[ "$actual_count" != "$expected_count" ]]; then
    echo "FAIL: $message" >&2
    echo "  expected count: $expected_count" >&2
    echo "  actual count: $actual_count" >&2
    echo "  pattern: $pattern" >&2
    echo "  in file: $file" >&2
    exit 1
  fi
}

assert_space_presence_stops_efc_scene_monitoring() {
  local file="SunSmart/Main/Space/Controller/SpaceViewController.swift"

  if ! awk '
    /private func stopSpacePresenceTracking\(reason: SpacePresenceStopReason\)/ {
      in_function = 1
      found_function = 1
    }
    in_function {
      line = $0
      if (line ~ /stopEmergencyFireSceneMonitoring\(\)/) {
        found_call = 1
      }
      opens = gsub(/\{/, "{", line)
      closes = gsub(/\}/, "}", line)
      depth += opens - closes
      if (found_function && depth == 0) {
        in_function = 0
      }
    }
    END {
      exit(found_function && found_call ? 0 : 1)
    }
  ' "$file"; then
    echo "FAIL: Space presence cleanup must stop EFC scene monitoring so global observers do not accumulate across Space re-entry." >&2
    echo "  expected stopSpacePresenceTracking(reason:) to call stopEmergencyFireSceneMonitoring()" >&2
    echo "  in file: $file" >&2
    exit 1
  fi
}

assert_efc_status_legend_fits_iphone16() {
  local file="SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireAlarmStatusLegendHeaderView.swift"
  local iphone16_width=393
  local iphone_standard_width=375
  local outer_inset=20
  local icon_title_spacing=4
  local required_text_width=148
  local minimum_slack=12

  local horizontal_inset
  local item_spacing
  local indicator_size
  horizontal_inset=$(awk -F'SCRXFrom\\(|\\)' '/horizontalInset = SCRXFrom/ { print $2; exit }' "$file")
  item_spacing=$(awk -F'SCRXFrom\\(|\\)' '/itemSpacing = SCRXFrom/ { print $2; exit }' "$file")
  indicator_size=$(awk -F'SCRXFrom\\(|\\)' '/indicatorSize = SCRXFrom/ { print $2; exit }' "$file")

  awk \
    -v iphone16_width="$iphone16_width" \
    -v iphone_standard_width="$iphone_standard_width" \
    -v outer_inset="$outer_inset" \
    -v horizontal_inset="$horizontal_inset" \
    -v item_spacing="$item_spacing" \
    -v indicator_size="$indicator_size" \
    -v icon_title_spacing="$icon_title_spacing" \
    -v required_text_width="$required_text_width" \
    -v minimum_slack="$minimum_slack" \
    'BEGIN {
      scale = iphone16_width / iphone_standard_width
      available = iphone16_width - (outer_inset * 2 * scale) - (horizontal_inset * 2 * scale)
      required = (indicator_size * 3 * scale) + (icon_title_spacing * 3 * scale) + (item_spacing * 2 * scale) + required_text_width + minimum_slack
      if (available < required) {
        printf("FAIL: EFC status legend must fit Triggered/Resume/Inactive on iPhone 16.\n") > "/dev/stderr"
        printf("  available: %.2f, required: %.2f\n", available, required) > "/dev/stderr"
        printf("  reduce fixed horizontal inset/spacing in %s\n", "'$file'") > "/dev/stderr"
        exit 1
      }
    }'
}

assert_efc_status_legend_fits_iphone16

assert_not_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift" \
  "Set Brightness t[o]" \
  "EFC restore action option must use Set Brightness To."

assert_not_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireEditState.swift" \
  "Set Brightness t[o]" \
  "EFC restore brightness row must use Set Brightness To."

assert_contains "SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift" \
  "case .all:" \
  "Restore filter must handle the default mode explicitly."

assert_contains "SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift" \
  "return node.deviceType != .emergencyController" \
  "Restore Device Data must not list EFC devices in default mode."

assert_contains "SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift" \
  "node.deviceType != .gateway && node.deviceType != .emergencyController" \
  "Restore Device Data must not list EFC devices in current-space non-gateway mode."

assert_contains "SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift" \
  "appendEmergencyFireControllerGroupMutationMessages(node: node, group: group, appendMessages: &appendMessages)" \
  "Classic Add Device group-add must append EFC group mutation messages."

assert_contains "SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift" \
  "appendEmergencyFireControllerGroupMutationMessages(node: node, group: group, appendMessages: &appendMessages)" \
  "Professional Add Device group-add must append EFC group mutation messages."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift" \
  "self.openSyncAfterLinkedDeviceIfNeeded()" \
  "Bind to a new EFC must enter the EFC sync flow after Add Device is dismissed when there is syncable group configuration."

assert_not_contains "SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift" \
  "appendLinkedEmergencyFireControllerGroupSubscriptionMessages(controller: controller, appendMessages: &appendMessages)" \
  "Classic EFC LINK must not append associated group subscription messages during Add Device."

assert_not_contains "SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift" \
  "appendLinkedEmergencyFireControllerGroupSubscriptionMessages(controller: controller, appendMessages: &appendMessages)" \
  "Professional EFC LINK must not append associated group subscription messages during Add Device."

assert_not_contains "SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift" \
  "linkedEmergencyFireGroupSubscriptionMessageHandles" \
  "Classic Add Device must not track linked EFC group subscription handles in fast-add append state."

assert_not_contains "SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift" \
  "linkedEmergencyFireGroupSubscriptionMessageHandles" \
  "Professional Add Device must not track linked EFC group subscription handles in fast-add append state."

assert_contains "SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift" \
  "finishLinkedEmergencyFireControllerConfiguration(for: node)" \
  "Classic EFC LINK must finish controller and associated group sync state together."

assert_contains "SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift" \
  "finishLinkedEmergencyFireControllerConfiguration(for: node)" \
  "Professional EFC LINK must finish controller and associated group sync state together."

assert_not_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift" \
  "self.dismiss(animated: true) { \[weak self\] in" \
  "EFC LINK callback must not dismiss again because DeviceAddViewController already closes the Add Device flow before invoking the callback."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift" \
  "items = try planner.makeAssociatedGroupItems()" \
  "EFC LINK sync must build associated group subscription items explicitly."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift" \
  'filter { !\$0\.tasks\.isEmpty }' \
  "EFC LINK sync must ignore associated groups that do not produce subscription tasks."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift" \
  "items: items" \
  "EFC LINK sync must pass limited associated group items to SyncDevicesViewController."

assert_count "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift" \
  "SyncDevicesViewController(type: \.emergencyFire(data: device, items: nil, context: \.saveConfiguration(persistsSyncResult: true, changedFromConfiguration: nil)))" \
  "1" \
  "Only the manual/current-device sync entry may use nil EFC items; LINK sync must pass associated group items."

assert_not_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift" \
  "notifySpaceDataChanged(type: \.common)" \
  "EFC create/save/delete/link must not use slow common sync."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift" \
  "notifySpaceDataChanged(type: .device)" \
  "EFC create/save/delete/link must use promptly device sync."

assert_contains "SunSmart/Common/Data/ImportData.swift" \
  "emergencyFireControllerCount" \
  "Space import summary must include EFC controller count."

assert_contains "SunSmart/Common/Data/ImportData.swift" \
  "json\\[\"emergencyFireControllers\"\\]\\.exists()" \
  "Space import must distinguish missing EFC payload from an explicit empty EFC list."

assert_contains "SunSmart/Common/Data/ImportData.swift" \
  "DeviceEmerFireStore.shared.devices(in: self)" \
  "Space import must merge real EFC nodes with the current Space context after importing controllers."

assert_contains "SunSmart/Common/Data/ExportData.swift" \
  "spaceJsonData.updateValue(emergencyFireControllerDicts, forKey: \"emergencyFireControllers\")" \
  "Space export must include EFC controllers in cloud payload."

assert_contains "SunSmart/Common/Data/ExportData.swift" \
  "dict.updateValue(configuration, forKey: \"configuration\")" \
  "Space export must include EFC controller configuration."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmControllerSyncVC.swift" \
  "spaceDataChangedNotificaitonName" \
  "Persisted EFC sync result must trigger Space cloud sync."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmControllerSyncVC.swift" \
  "SpaceChangeDataType.device" \
  "Persisted EFC sync result must use promptly device cloud sync."

assert_contains "SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift" \
  "flowLayout.minimumLineSpacing = itemMargin" \
  "Others page must use the shared itemMargin for line spacing so iPad EFC items match Lights."

assert_contains "SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift" \
  "flowLayout.minimumInteritemSpacing = itemMargin" \
  "Others page must use the shared itemMargin for interitem spacing so iPad EFC items match Lights."

assert_contains "SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift" \
  "flowLayout.itemRowCount = columnNum" \
  "Others page must tell AlignCenterFlowLayout the configured column count."

assert_contains "SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift" \
  "collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(50 + (isIPad ? 22 : 10)), left: collectionViewMargin, bottom: 0, right: collectionViewMargin)" \
  "Others page iPad content inset must match Lights so EFC cards have the same width budget."

assert_contains "SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift" \
  "MeshLibManager.manager.messageDelegate = self" \
  "Others page must receive Mesh data updates while visible so EFC online/offline changes refresh in place."

assert_contains "SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift" \
  "extension DeviceOthersViewController: MeshLibManagerMessageDelegate" \
  "Others page must implement the Mesh data update delegate for EFC status refresh."

assert_contains "SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift" \
  "reloadEmergencyFireItem(for: node)" \
  "Mesh data updates for an EFC node must refresh the matching Others item."

assert_contains "SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift" \
  "openEmergencyFireEdit(for device: DeviceEmerFireData)" \
  "Others page must share one EFC Edit route between tap fallback and long press."

assert_contains "SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift" \
  "XWHUDManager.showTipHUD(\"no_permission\".localizedString" \
  "Others page EFC long press Edit route must respect edit permission."

assert_contains "SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift" \
  "case .emergencyFireController(let device):" \
  "Others page long press must handle EFC items."

assert_not_contains "SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift" \
  "device.displayStatus == .unboundDevice || device.displayStatus == .syncIssueDevice" \
  "Others page short tap must not send unlinked virtual EFC directly to Edit."

assert_contains "SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift" \
  "if device.displayStatus == .syncIssueDevice" \
  "Others page short tap should still route sync-issue EFC to Edit."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift" \
  "guardLinkedDeviceForAction()" \
  "EFC device page actions must share an unlinked-device guard."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/EmerFireAlarmMonitorViewModel.swift" \
  "var isEffectiveVisitor: Bool" \
  "EFC monitor must expose a page-local Visitor predicate."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/EmerFireAlarmMonitorViewModel.swift" \
  "!canConfigureDevice" \
  "EFC monitor effective Visitor predicate must include active-user permission downgrade."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift" \
  "showRealEmergencyFireControllerVisitorMenu()" \
  "Real EFC Visitor menu must use a dedicated Information-only branch."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift" \
  "makeInformationMenuItem()" \
  "EFC Information menu item must be shared by normal and Visitor real-device menus."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift" \
  "guard !viewModel.isEffectiveVisitor else { return }" \
  "Virtual EFC Visitor menu must expose no options."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift" \
  "guardVisitorCanUseMockAction()" \
  "EFC Mock actions must share a Visitor permission guard."

assert_count "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift" \
  "guard guardVisitorCanUseMockAction()" \
  "3" \
  "Fire Alarm, Power Loss, and Restore Mock actions must all check Visitor permission first."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift" \
  "\"Insufficient permissions\".localizedString" \
  "Visitor Mock action denial must show the requested localized Toast."

assert_contains "SunSmart/en.lproj/Localizable.strings" \
  "\"Insufficient permissions\" = \"Insufficient permissions\";" \
  "English localization must include Insufficient permissions."

assert_contains "SunSmart/zh-Hans.lproj/Localizable.strings" \
  "\"Insufficient permissions\" = \"权限不足\";" \
  "Simplified Chinese localization must include Insufficient permissions."

assert_count "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift" \
  "guard guardLinkedDeviceForAction()" \
  "4" \
  "Identify and three Mock actions must all guard unlinked virtual EFC before executing."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift" \
  "isUnlinkedVirtualEmergencyFireController" \
  "EFC device page menu must explicitly identify unlinked virtual EFC."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift" \
  "showUnlinkedVirtualEmergencyFireControllerMenu" \
  "Unlinked virtual EFC menu must be separated from real EFC menu items."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift" \
  "deleteUnlinkedVirtualEmergencyFireController" \
  "Unlinked virtual EFC Delete must use a local-only deletion flow."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift" \
  "confirmDeleteEmergencyFireControllerDeviceOrVirtual(" \
  "EFC delete must expose one shared entry that handles real and virtual controller deletion."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift" \
  "guard space?.deviceOperates.contains(.delete) ?? false else" \
  "Shared EFC delete entry must guard Delete permission before showing confirmation."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift" \
  "device.bindNode == nil" \
  "Shared EFC delete entry must detect unlinked virtual EFC before real-device cleanup."

assert_contains "SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift" \
  "confirmDeleteEmergencyFireControllerDeviceOrVirtual(" \
  "Others EFC delete must use the same shared delete entry as the EFC device page."

assert_not_contains "SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift" \
  "confirmDeleteEmergencyFireControllerDevice(" \
  "Others EFC delete must not bypass the shared real/virtual delete entry."

assert_contains "SunSmart/en.lproj/Localizable.strings" \
  "Are you sure to delete the EFC device?" \
  "English localization must include virtual EFC delete confirmation."

assert_contains "SunSmart/zh-Hans.lproj/Localizable.strings" \
  "Are you sure to delete the EFC device?" \
  "Chinese localization must include virtual EFC delete confirmation key."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift" \
  "confirmDeleteEmergencyFireControllerDevice(" \
  "EFC device page Delete must use the shared device deletion flow."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift" \
  "deleteNodes(nodes: \\[node\\])" \
  "EFC device deletion must send Reset through DeviceProtocol.deleteNodes."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift" \
  "navigationController?.presentingViewController != nil" \
  "EFC device page close/back must dismiss a presented navigation controller root after Delete."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift" \
  "navigationController?.dismiss(animated: true)" \
  "EFC device page close/back must dismiss the modal navigation controller when it is the presented container."

assert_not_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift" \
  "clearMonitoringConfiguration(for: device)" \
  "EFC device page Delete must not only clear monitoring configuration."

assert_contains "SunSmart/Main/Space/Controller/SyncDevicesViewController.swift" \
  "enum EmergencyFireSyncContext" \
  "EFC sync must distinguish SAVE and Delete contexts."

assert_contains "SunSmart/Main/Space/Controller/SyncDevicesViewController.swift" \
  "case deleteCleanup" \
  "EFC Delete sync must have an explicit delete cleanup context."

assert_contains "SunSmart/Main/Space/Controller/SyncDevicesViewController.swift" \
  "context.isDeleteCleanup" \
  "EFC Delete sync retry must remain delete-only."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift" \
  "context: .deleteCleanup" \
  "EFC Delete flow must enter Sync Devices with Delete cleanup context."

assert_not_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift" \
  "var items = makeDisableControllerItems()" \
  "EFC Delete cleanup must not send controller disable tasks."

assert_not_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift" \
  "items.append(contentsOf: makeDisableControllerItems())" \
  "EFC Delete cleanup must not include controller body tasks."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift" \
  "ConfigModelSubscriptionDelete" \
  "EFC Delete cleanup must clear group subscriptions."

assert_not_contains "SunSmart/Main/Space/Controller/SyncDevicesViewController.swift" \
  "|| self.isEmergencyFireControllerDeleteCleanup(model)" \
  "EFC Delete cleanup must not bypass Mesh result failure detection."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift" \
  "makeDeleteCleanupTasks" \
  "EFC Delete cleanup must split each unsubscribe handle into its own task."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift" \
  "handles.map { handle in" \
  "EFC Delete cleanup must map every unsubscribe handle to an independent task."

assert_contains "SunSmart/Main/Space/Controller/SyncDevicesViewController.swift" \
  "isSyncOperationSuccessful(" \
  "Sync success handling must use a general helper instead of Battery Power Switch-specific naming."

assert_not_contains "SunSmart/Main/Space/Controller/SyncDevicesViewController.swift" \
  "if self.isBatteryPowerSwitchOperationSuccessful(" \
  "EFC Delete cleanup must not be evaluated through the Battery Power Switch success helper."

assert_contains "SunSmart/Main/Space/Controller/SyncDevicesViewController.swift" \
  "isEmergencyFireControllerDeleteCleanupSuccessful(" \
  "EFC Delete cleanup must have an explicit result-based success predicate."

assert_contains "SunSmart/Main/Space/Controller/SyncDevicesViewController.swift" \
  "prepareTaskForResync(task)" \
  "Progress retry for a single task must reset task retry state through a shared helper."

assert_contains "SunSmart/Main/Space/Controller/SyncDevicesViewController.swift" \
  "resetMessageHandlesForResync" \
  "Retry must clear stale MeshMessageHandle response state before resending."

assert_contains "SunSmart/Main/Space/Controller/SyncDevicesViewController.swift" \
  "handle.respondAddresss = \\[\\]" \
  "Retry must clear stale responded addresses before resending."

assert_contains "SunSmart/Main/Space/Controller/SyncDevicesViewController.swift" \
  "handle.notRespondAddresss = \\[\\]" \
  "Retry must clear stale missing addresses before resending."

assert_contains "SunSmart/Main/Space/Controller/SyncDevicesViewController.swift" \
  "[EFC Delete Cleanup]" \
  "EFC Delete cleanup retries must log task-level result details."

assert_contains "SunSmart/Main/Space/Controller/SyncDevicesViewController.swift" \
  "emergencyFireDeleteCleanupRetryPolicy" \
  "EFC Delete cleanup tasks must have an explicit retry policy."

assert_contains "SunSmart/Main/Space/Controller/SyncDevicesViewController.swift" \
  "maxRetries: 2" \
  "EFC Delete cleanup must retry twice before marking a task failed."

assert_contains "SunSmart/Main/Space/Controller/SyncDevicesViewController.swift" \
  "retryDelay: 0.2" \
  "EFC Delete cleanup retry delay must be long enough for the mesh command queue to reset."

assert_contains "SunSmart/Main/Space/Controller/SyncDevicesViewController.swift" \
  "willRetry=" \
  "EFC Delete cleanup retry decisions must be visible in logs."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData+Sync.swift" \
  "markDeleteCleanupInterrupted" \
  "EFC Delete cleanup failures must be persisted immediately."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData+Sync.swift" \
  "markDeleteCleanupSucceeded" \
  "EFC Delete cleanup successful groups must be removed from associate groups."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift" \
  "associatedGroupSubscriptionModelIDs" \
  "EFC associated group subscription must use a fixed candidate model set."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift" \
  "node.getFunctionModels(modelId: modelID)" \
  "EFC associated group subscription must only create tasks for models the node actually owns."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlan.swift" \
  "case associationSubscription = \"efc_sync_group_subscription\"" \
  "EFC associated group subscription tasks must use the generic subscription task kind."

assert_not_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift" \
  "restoreSettings.actionType == .restoreAuto" \
  "EFC group subscriptions must not depend on Restore AUTO."

assert_not_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift" \
  "makeNonAutoRestoreCleanupTask" \
  "EFC must not clean Light LC subscriptions just because Event Ends is not Restore AUTO."

assert_not_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift" \
  "includeLightLC" \
  "EFC cleanup must not use action-type-specific Light LC cleanup flags."

assert_not_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift" \
  "makeHistoricalSceneCleanupMessageHandles" \
  "EFC subscription sync must not keep historical Scene Server cleanup while groups are still associated."

assert_not_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift" \
  "sceneModel" \
  "EFC subscription sync must not delete Scene Server subscriptions in the current test-stage data model."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireConfig.swift" \
  "var enabled: Bool {" \
  "EFC enabled state must remain fixed on."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift" \
  "Not executed. Please link a group first." \
  "EFC Mock actions must show a group-first toast when no group is associated."

assert_count "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift" \
  "guard guardMockActionHasAssociatedGroup()" \
  "3" \
  "Each EFC Mock action must use the group-first guard before sending commands."

assert_not_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireEditRow.swift" \
  "case enabled" \
  "Edit device must not expose an enabled row."

assert_not_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireEditRow.swift" \
  "case fireAlarmAction" \
  "Edit device must not expose Fire Alarm action preset selection."

assert_not_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireEditRow.swift" \
  "case powerLossAction" \
  "Edit device must not expose Power Loss action preset selection."

assert_not_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift" \
  "EmergencyFireActionPresetSelectionController" \
  "Edit device must not provide an action preset selector."

assert_not_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift" \
  "Fire Alarm Action" \
  "Edit device must not show a Fire Alarm Action row."

assert_not_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift" \
  "Power Loss Action" \
  "Edit device must not show a Power Loss Action row."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift" \
  "efc_waiting_for_setup" \
  "Report To Gateway must keep the current waiting-for-setup placeholder."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Add/Controller/PJDevicesFireAlarmAddContainerController.swift" \
  "vc.bindTarget = context.bindTarget" \
  "Legacy FireAlarm add container must forward bindTarget."

assert_contains "/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift" \
  "addGlobalMessageObserver" \
  "SDK must expose a global message observer for Space-level EFC scene dispatch."

assert_contains "SunSmart/Main/Space/Controller/SpaceViewController.swift" \
  "registerEmergencyFireSceneMessageObserverIfNeeded()" \
  "Space must register the global EFC scene message observer after activating the scene manager."

assert_contains "SunSmart/Main/Space/Controller/SpaceViewController.swift" \
  "removeEmergencyFireSceneMessageObserver()" \
  "Space must remove the global EFC scene message observer when leaving the Space lifecycle."

assert_contains "SunSmart/Main/Space/Controller/SpaceViewController.swift" \
  "stopEmergencyFireSceneMonitoring()" \
  "Space must centralize EFC scene monitoring cleanup."

assert_contains "SunSmart/Main/Space/Controller/SpaceViewController.swift" \
  "guard !hasStoppedPresenceTracking else { return }" \
  "Space must not register EFC scene monitoring from an async load callback after the Space has already stopped."

assert_space_presence_stops_efc_scene_monitoring

assert_count "SunSmart/Main/Space/Controller/SpaceViewController.swift" \
  "EmergencyFireControllerSceneEventManager.dispatch(message: message, source: source, destination: destination)" \
  "1" \
  "Only SpaceViewController should dispatch EFC scene messages from the global observer."

if grep -R "EmergencyFireControllerSceneEventManager.dispatch(message: message, source: source, destination: destination)" \
  SunSmart/Main/Device SunSmart/Main/Group SunSmart/Main/Space/TriggerZone; then
  echo "FAIL: Page-level EFC scene dispatch must be removed; Space global observer owns dispatch." >&2
  exit 1
fi

echo "EFC controller flow contracts passed."
