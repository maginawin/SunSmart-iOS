#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
app_root="$(cd "$script_dir/.." && pwd)"
sdk_root="$(cd "$app_root/../../nordic-sig-mesh-sdk" && pwd)"

assert_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"

  if ! rg -Fq -- "$pattern" "$file"; then
    echo "FAIL: $message" >&2
    echo "  expected: $pattern" >&2
    echo "  file: $file" >&2
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"

  if rg -Fq -- "$pattern" "$file"; then
    echo "FAIL: $message" >&2
    echo "  unexpected: $pattern" >&2
    echo "  file: $file" >&2
    exit 1
  fi
}

kinetic_file="$sdk_root/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshEnOceanProxyServer.swift"
efc_sync_file="$app_root/SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData+Sync.swift"
group_server_file="$app_root/SunSmart/Main/Group/Model/GroupServer.swift"
battery_config_file="$sdk_root/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift"
neighbor_api_file="$sdk_root/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift"

assert_contains "$kinetic_file" \
  "ttl: 0xFF, period: .disabled, retransmit: .disabled" \
  "Kinetic Proxy Model Publication must use the Proxy Node default TTL sentinel."
assert_not_contains "$kinetic_file" \
  "ttl: MeshNetworkManager.instance.networkParameters.defaultTtl" \
  "Kinetic Proxy Model Publication must not use the App network TTL."

assert_contains "$efc_sync_file" \
  "static let emergencyActionTTL: UInt8 = 0xFF" \
  "EFC Action Config must keep using the device default TTL sentinel."
assert_contains "$efc_sync_file" \
  "ttl: 0xFF," \
  "EFC Scene Publication must use the EFC Node default TTL sentinel."
assert_not_contains "$efc_sync_file" \
  "ttl: MeshNetworkManager.instance.networkParameters.defaultTtl" \
  "EFC Scene Publication must not use the App network TTL."

assert_contains "$group_server_file" \
  "proximityLightingNeighborSet(enabled: true, relay: relayNumber, ttl: 0xFF" \
  "The previously nonzero Group Add Neighbor Config must use 0xFF."
assert_not_contains "$group_server_file" \
  "proximityLightingNeighborSet(enabled: true, relay: relayNumber, ttl: MeshNetworkManager.instance.networkParameters.defaultTtl" \
  "The Group Add Neighbor Config must not use the App network TTL."

assert_contains "$app_root/SunSmart/Common/Data/Node+MessageHandles.swift" \
  "proximityLightingNeighborSet(enabled: true, relay: relayNumber, ttl: 0" \
  "The general Node sync Neighbor Config must keep TTL 0."
assert_contains "$app_root/SunSmart/Main/Space/Model/SyncDevicesCellModel.swift" \
  "proximityLightingNeighborSet(enabled: true, relay: relayNumber, ttl: 0" \
  "The Space sync Neighbor Config must keep TTL 0."
assert_contains "$app_root/SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift" \
  "proximityLightingNeighborSet(enabled: true, relay: relayNumber, ttl: 0" \
  "The EFC sync Neighbor Config must keep TTL 0."

assert_contains "$battery_config_file" \
  "ttl: UInt8 = 0xFF," \
  "Battery/AC Power Switch Key Config must keep its 0xFF default TTL."
assert_contains "$neighbor_api_file" \
  "case proximityLightingNeighborSet(enabled: Bool, relay: UInt8, ttl: UInt8 = 0," \
  "The Neighbor Config SDK API default must remain TTL 0."

echo "PASS: device default TTL payload contracts"
