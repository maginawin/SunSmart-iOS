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
