#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "$script_dir/lib/resolve_nordic_sdk_root.sh"
sdk_root="$(resolve_nordic_sdk_root "$repo_root" "${1:-}")"

assert_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if ! rg -q "$pattern" "$file"; then
    echo "FAIL: $message"
    echo "  file: $file"
    echo "  expected pattern: $pattern"
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if rg -q "$pattern" "$file"; then
    echo "FAIL: $message"
    echo "  file: $file"
    echo "  unexpected pattern: $pattern"
    exit 1
  fi
}

assert_match_count() {
  local file="$1"
  local pattern="$2"
  local expected="$3"
  local message="$4"
  local actual
  actual="$(rg -c "$pattern" "$file" || true)"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $message"
    echo "  file: $file"
    echo "  expected count: $expected"
    echo "  actual count: $actual"
    exit 1
  fi
}

settings_file="${repo_root}/SunSmart/Common/Data/LabSettings.swift"
app_delegate_file="${repo_root}/SunSmart/AppDelegate/AppDelegate.swift"
lab_file="${repo_root}/SunSmart/Main/Site/Controller/LabViewController.swift"
helper_file="${repo_root}/SunSmart/Common/Data/LightGroupControlCommandSender.swift"
ack_file="${repo_root}/SunSmart/Main/Device/Lights/Model/LightAckProgressTracker.swift"
lights_file="${repo_root}/SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift"
light_detail_file="${repo_root}/SunSmart/Main/Device/Controller/DeviceLightViewController.swift"
en_strings="${repo_root}/SunSmart/en.lproj/Localizable.strings"
zh_strings="${repo_root}/SunSmart/zh-Hans.lproj/Localizable.strings"
sdk_manager="${sdk_root}/Sources/NordicSigMeshSDK/nRFMeshProvision/MeshNetworkManager.swift"
sdk_policy="${sdk_root}/Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/OutgoingAccessMessageTtlPolicy.swift"
sdk_access_layer="${sdk_root}/Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/Access Layer/AccessLayer.swift"
sdk_lower_transport="${sdk_root}/Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/Lower Transport Layer/LowerTransportLayer.swift"
sdk_tests="${sdk_root}/Tests/NordicSigMeshSDKTests/OutgoingAccessMessageTtlPolicyTests.swift"
sdk_standalone_tests="${sdk_root}/Tests/Standalone/OutgoingAccessMessageTtlPolicyTests.swift"

for file in \
  "$settings_file" \
  "$app_delegate_file" \
  "$lab_file" \
  "$helper_file" \
  "$ack_file" \
  "$lights_file" \
  "$light_detail_file" \
  "$en_strings" \
  "$zh_strings" \
  "$sdk_manager" \
  "$sdk_policy" \
  "$sdk_access_layer" \
  "$sdk_lower_transport" \
  "$sdk_tests" \
  "$sdk_standalone_tests"; do
  test -f "$file" || {
    echo "FAIL: required TTL contract file is missing"
    echo "  file: $file"
    exit 1
  }
done

assert_contains "$settings_file" 'overrideOutgoingMeshTTL' "LabSettings must store the outgoing Mesh TTL override switch"
assert_contains "$settings_file" 'outgoingMeshTTLOverride' "LabSettings must expose the optional outgoing Mesh TTL override"
assert_contains "$settings_file" 'lab_override_light_group_control_ttl' "The existing override UserDefaults key must be preserved"
assert_contains "$settings_file" 'lab_light_group_control_ttl' "The existing TTL UserDefaults key must be preserved"
assert_contains "$settings_file" 'min\(max\(.*0\).*127\)' "LabSettings must clamp TTL to 0...127"
assert_contains "$settings_file" 'MeshNetworkManager\.setOutgoingAccessMessageTtlOverride\(outgoingMeshTTLOverride\)' "LabSettings must synchronize the SDK override"
assert_contains "$app_delegate_file" 'LabSettings\.applyOutgoingMeshTTLOverride\(\)' "App launch must restore the persisted SDK override"

assert_contains "$lab_file" 'overrideOutgoingMeshTTL' "Lab must show the outgoing Mesh TTL override switch"
assert_contains "$lab_file" 'outgoing_mesh_ttl_scope' "Lab must explain the global Network PDU TTL scope"
assert_contains "$lab_file" 'visibleRows' "Lab must hide the TTL value while override is disabled"
assert_contains "$lab_file" 'visibleRows\.count' "Lab row count must follow visible rows"
assert_contains "$lab_file" 'tableView\.reloadData\(\)' "Lab must refresh after switch and value changes"
assert_not_contains "$lab_file" 'lightGroupControlTTL' "Lab UI symbols must no longer claim Light/Group-only scope"

assert_contains "$sdk_manager" 'public static var outgoingAccessMessageTtlOverride' "SDK must expose the global outgoing Access TTL override"
assert_contains "$sdk_manager" 'setOutgoingAccessMessageTtlOverride' "SDK must expose a validated override setter"
assert_contains "$sdk_manager" 'ttl == nil \|\| ttl! <= 127' "SDK must reject TTL values above 127"
assert_contains "$sdk_manager" 'outgoingAccessMessageTtlOverrideLock' "SDK global override access must be synchronized"
assert_contains "$sdk_policy" 'override \?\? initialTtl \?\? provisionerDefaultTtl \?\? networkDefaultTtl' "SDK policy must give Lab override the highest priority"
assert_match_count "$sdk_access_layer" 'OutgoingAccessMessageTtlPolicy\.resolve' 1 "Acknowledged message retry timing must resolve the effective outgoing Access TTL"
assert_contains "$sdk_access_layer" 'acknowledgmentMessageInterval\(forTtl: ttl' "Acknowledged message retry timing must use the effective outgoing Access TTL"
assert_match_count "$sdk_lower_transport" 'OutgoingAccessMessageTtlPolicy\.resolve' 2 "Only segmented and unsegmented Access Message exits must apply the override"
assert_contains "$sdk_tests" 'testOverrideHasHighestPriority' "SDK tests must cover override priority"
assert_contains "$sdk_tests" 'testAcknowledgmentIntervalUsesOverrideTtl' "SDK tests must cover the override TTL acknowledgment interval"
assert_contains "$sdk_tests" 'testAcknowledgmentIntervalKeepsSegmentCountCompensation' "SDK tests must preserve acknowledgment segment compensation"
assert_contains "$sdk_tests" 'testGlobalOverrideRejectsValueAbove127WithoutChangingCurrentValue' "SDK tests must cover invalid TTL rejection"
assert_contains "$sdk_standalone_tests" 'OutgoingAccessMessageTtlPolicy\.resolve' "Standalone SDK policy test must execute the production resolver"

assert_contains "$helper_file" 'enum LightGroupControlCommandSender' "Existing Light/Group message construction helper must remain available"
assert_not_contains "$helper_file" 'LabSettings' "Light/Group helper must not own the global TTL policy"
assert_not_contains "$helper_file" 'defaultTTL:' "Light/Group helper must not inject TTL per command"
assert_contains "$ack_file" 'defaultTTL: UInt8\? = nil' "ACK tracker must continue accepting the diagnostic App Tx TTL"
assert_contains "$ack_file" 'defaultTTL: defaultTTL' "ACK tracker must pass its diagnostic TTL to MeshAPI"
assert_contains "$lights_file" 'defaultTTL: LabSettings\.outgoingMeshTTLOverride' "Lights ACK diagnostics must show the global App Tx TTL"
assert_contains "$light_detail_file" 'defaultTTL: LabSettings\.outgoingMeshTTLOverride' "Light detail ACK diagnostics must show the global App Tx TTL"

assert_contains "$en_strings" '"override_outgoing_mesh_ttl" = "Override Outgoing Mesh TTL";' "English switch text must describe outgoing Mesh scope"
assert_contains "$en_strings" '"outgoing_mesh_ttl" = "Outgoing Mesh TTL";' "English TTL row text must describe outgoing Mesh scope"
assert_contains "$en_strings" 'Embedded TTL fields are unchanged' "English scope text must distinguish payload TTL fields"
assert_contains "$zh_strings" '"override_outgoing_mesh_ttl" = "覆盖下行 Mesh TTL";' "Simplified Chinese switch text must describe outgoing Mesh scope"
assert_contains "$zh_strings" '"outgoing_mesh_ttl" = "下行 Mesh TTL";' "Simplified Chinese TTL row text must describe outgoing Mesh scope"
assert_contains "$zh_strings" '消息载荷内的 TTL 字段不变' "Simplified Chinese scope text must distinguish payload TTL fields"
assert_not_contains "$en_strings" 'override_light_group_control_ttl' "Old Light/Group-only English key must be removed"
assert_not_contains "$zh_strings" 'override_light_group_control_ttl' "Old Light/Group-only Chinese key must be removed"

echo "PASS: Lab global outgoing Mesh TTL contract"
