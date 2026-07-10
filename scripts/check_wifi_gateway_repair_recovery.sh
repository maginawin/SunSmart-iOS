#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

message_handles="SunSmart/Common/Data/Node+MessageHandles.swift"
cell_model="SunSmart/Main/Space/Model/SyncDevicesCellModel.swift"
sync_controller="SunSmart/Main/Space/Controller/SyncDevicesViewController.swift"
gateway_controller="SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift"
wifi_controller="SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift"
en_strings="SunSmart/en.lproj/Localizable.strings"
zh_strings="SunSmart/zh-Hans.lproj/Localizable.strings"

rg -n "func getGatewayRepairCompositionMessageHandles\\(\\) -> \\[MeshMessageHandle\\]" "$message_handles" >/dev/null \
  || fail "Repair must expose a Composition-stage builder"
rg -n "ConfigCompositionDataGet\\(\\)" "$message_handles" >/dev/null \
  || fail "Repair Composition builder must send ConfigCompositionDataGet"
rg -n "func getGatewayRepairInitializationMessageHandles\\(\\) -> \\[MeshMessageHandle\\]" "$message_handles" >/dev/null \
  || fail "Repair must expose a post-Composition initialization builder"
rg -n "getForcedGatewayInitializationMessageHandles\\(\\)" "$message_handles" >/dev/null \
  || fail "Repair initialization must reuse forced Gateway key/bind handles"
rg -n "getConfigMessageHandles\\(\\)\\.filter" "$message_handles" >/dev/null \
  || fail "Repair initialization must append remaining normal configuration"
rg -n "ConfigNetKeyAdd|ConfigAppKeyAdd|ConfigModelAppBind" "$message_handles" >/dev/null \
  || fail "Repair initialization must explicitly filter duplicate key/bind messages"
rg -n "case gatewayRepairInitialization" "$cell_model" >/dev/null \
  || fail "ActionType must define gatewayRepairInitialization"
rg -n "getGatewayRepairCompositionMessageHandles\\(\\)" "$cell_model" >/dev/null \
  || fail "Repair action must choose the Composition stage first"
awk '
  /case \.gatewayRepairInitialization:/ {
    getline
    if ($0 ~ /return node\.isKeybindComplete/) found = 1
  }
  END { exit(found ? 0 : 1) }
' "$cell_model" \
  || fail "Repair initialization success must require isKeybindComplete"

rg -n "enum GatewayRecoveryTrigger" "$sync_controller" >/dev/null \
  || fail "Sync controller must define a Gateway Recovery trigger"
rg -n "case devicesNotSynced" "$sync_controller" >/dev/null \
  || fail "Gateway Recovery trigger must define devicesNotSynced"
rg -n "case repair" "$sync_controller" >/dev/null \
  || fail "Gateway Recovery trigger must define Repair"
rg -n "case gatewayRecovery\\(" "$sync_controller" >/dev/null \
  || fail "SyncType must define Gateway Recovery"
rg -n "trigger: GatewayRecoveryTrigger" "$sync_controller" >/dev/null \
  || fail "Gateway Recovery SyncType must carry the trigger"
rg -n "var startsImmediately: Bool" "$sync_controller" >/dev/null \
  || fail "Gateway Recovery trigger must define its initial run behavior"
rg -n "case gatewayRecoveryVerification\\(gateway: GatewayModel\\)" "$cell_model" >/dev/null \
  || fail "ActionType must define final Gateway Recovery verification"
rg -n "node\\.isKeybindComplete" "$cell_model" >/dev/null \
  || fail "Final verification must require key bind"
rg -n "node\\.getNodeSyncGatewayData\\(gateway: gateway\\)\\.isEmpty" "$cell_model" >/dev/null \
  || fail "Final verification must require an empty Gateway diff"
rg -n "GatewayServerAuthorizationService\\.isValid\\(gateway\\.mqttServerInfo\\)" "$cell_model" >/dev/null \
  || fail "WiFi Gateway final verification must require valid Server Information"
rg -n "isGatewayRepairInitialization" "$sync_controller" >/dev/null \
  || fail "Sync controller must identify the Repair initializer"
rg -n "statusMessage is ConfigCompositionDataStatus" "$sync_controller" >/dev/null \
  || fail "Repair must append initialization after Composition Status"
rg -n "getGatewayRepairInitializationMessageHandles\\(\\)" "$sync_controller" >/dev/null \
  || fail "Composition success must append forced Repair initialization"
rg -n "gateway_recovery_verification" "$sync_controller" "$en_strings" "$zh_strings" >/dev/null \
  || fail "Recovery verification task must be localized"

rg -n "func performGatewayRepair\(\)" "$gateway_controller" >/dev/null \
  || fail "Base Gateway controller must expose an overridable Repair hook"
rg -n "func resync\(trigger: SyncDevicesViewController\.GatewayRecoveryTrigger\)" "$gateway_controller" >/dev/null \
  || fail "Gateway recovery navigation must receive the trigger"
rg -n "resync\(trigger: \.devicesNotSynced\)" "$gateway_controller" >/dev/null \
  || fail "Devices not synced must use the devicesNotSynced trigger"
rg -n "isPresentingGatewayRecovery" "$gateway_controller" >/dev/null \
  || fail "Gateway recovery navigation must guard duplicate pushes"
rg -n "repairDevices\(nodes: \[node\]" "$gateway_controller" >/dev/null \
  || fail "Non-WiFi gateways must retain the legacy Repair implementation"
rg -n "override func performGatewayRepair\(\)" "$wifi_controller" >/dev/null \
  || fail "WiFi Gateway must override Repair"
rg -n "resync\(trigger: \.repair\)" "$wifi_controller" >/dev/null \
  || fail "WiFi Gateway Repair must enter full recovery"
rg -n "bottomView\.isHidden = true" "$wifi_controller" >/dev/null \
  || fail "WiFi Gateway Repair state must hide SAVE"
rg -n "bottomView\.isHidden = false" "$wifi_controller" >/dev/null \
  || fail "Configured WiFi Gateway state must restore SAVE visibility"
rg -n "guard node\.isKeybindComplete else" "$wifi_controller" >/dev/null \
  || fail "WiFi automatic status requests must wait for completed Key Bind"

echo "PASS: WiFi Gateway Repair initialization contracts"
