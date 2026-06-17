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

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData.swift" \
  "restoreDevice(replacing oldNode: Node, with newNode: Node, in space: SpaceData)" \
  "Restore must migrate an existing EFC local configuration to the restored node address."

assert_contains "SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift" \
  "restoreEmergencyFireControllerIfNeeded(oldNode: oldNode, newNode: node)" \
  "Restore provisioning must call the EFC restore helper."

assert_contains "SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift" \
  "prepareEmergencyFireControllerRestoreMessages(oldNode: oldNode, newNode: newNode, appendMessages: &appendMessages)" \
  "Restore append messages must include EFC planner output."

assert_contains "SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift" \
  "appendEmergencyFireControllerGroupMutationMessages(node: node, group: group, appendMessages: &appendMessages)" \
  "Classic Add Device group-add must append EFC group mutation messages."

assert_contains "SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift" \
  "appendEmergencyFireControllerGroupMutationMessages(node: node, group: group, appendMessages: &appendMessages)" \
  "Professional Add Device group-add must append EFC group mutation messages."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift" \
  "openSyncAfterLinkedDeviceIfNeeded()" \
  "Bind to a new EFC must enter the EFC sync flow when there is syncable configuration."

assert_contains "SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift" \
  "MeshLibManager.manager.messageDelegate = self" \
  "Others page must receive Mesh data updates while visible so EFC online/offline changes refresh in place."

assert_contains "SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift" \
  "extension DeviceOthersViewController: MeshLibManagerMessageDelegate" \
  "Others page must implement the Mesh data update delegate for EFC status refresh."

assert_contains "SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift" \
  "reloadEmergencyFireItem(for: node)" \
  "Mesh data updates for an EFC node must refresh the matching Others item."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireConfig.swift" \
  "var enabled: Bool {" \
  "EFC enabled state must remain fixed on."

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
  "Waiting for setup" \
  "Report To Gateway must keep the current waiting-for-setup placeholder."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Add/Controller/PJDevicesFireAlarmAddContainerController.swift" \
  "vc.bindTarget = context.bindTarget" \
  "Legacy FireAlarm add container must forward bindTarget."

echo "EFC controller flow contracts passed."
