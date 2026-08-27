#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
app_root="$(cd "$script_dir/.." && pwd)"
source "$script_dir/lib/resolve_nordic_sdk_root.sh"
sdk_root="$(resolve_nordic_sdk_root "$app_root" "${1:-}")"
access_message="$sdk_root/Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/Lower Transport Layer/AccessMessage.swift"
segmented_message="$sdk_root/Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/Lower Transport Layer/SegmentedAccessMessage.swift"
upper_transport="$sdk_root/Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/Upper Transport Layer/UpperTransportPdu.swift"
access_pdu="$sdk_root/Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/Access Layer/AccessPdu.swift"
access_layer="$sdk_root/Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/Access Layer/AccessLayer.swift"
network_manager="$sdk_root/Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/NetworkManager.swift"
receive_result="$sdk_root/Sources/NordicSigMeshSDK/nRFMeshProvision/MeshMessageReceiveResult.swift"
mesh_api="$sdk_root/Sources/NordicSigMeshSDK/MeshLib/MeshAPI.swift"
replay_event="$sdk_root/Sources/NordicSigMeshSDK/MeshLib/Diagnostics/MeshReplayProtectionDiscardEvent.swift"
lower_transport="$sdk_root/Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/Lower Transport Layer/LowerTransportLayer.swift"
ack_tracker="SunSmart/Main/Device/Lights/Model/LightAckProgressTracker.swift"
en_strings="SunSmart/en.lproj/Localizable.strings"
zh_strings="SunSmart/zh-Hans.lproj/Localizable.strings"

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

assert_contains_fixed() {
  local file="$1"
  local text="$2"
  local message="$3"
  if ! rg -Fq "$text" "$file"; then
    echo "FAIL: $message"
    echo "  file: $file"
    echo "  expected text: $text"
    exit 1
  fi
}

assert_contains "$access_message" "receivedTTL = networkPdu\\.ttl" "Unsegmented Access Message must preserve the received Network PDU TTL"
assert_contains "$segmented_message" "receivedTTL = networkPdu\\.ttl" "Each received segment must preserve its Network PDU TTL"
assert_contains "$access_message" "segmentTTLs\\.count == segments\\.count && receivedTTLs\\.count == 1" "Segmented Access Message must expose TTL only when all segments agree"
assert_contains "$upper_transport" "receivedTTL = accessMessage\\.receivedTTL" "Upper Transport must pass receive TTL metadata"
assert_contains "$access_pdu" "receivedTTL = pdu\\.receivedTTL" "Access PDU must pass receive TTL metadata"
assert_contains "$access_layer" "receivedTTL: accessPdu\\.receivedTTL" "Access Layer must notify with receive TTL metadata"

assert_contains "$receive_result" "public struct MeshMessageReceiveResult" "SDK must expose a message receive metadata result"
assert_contains "$receive_result" "public let receivedTTL: UInt8\\?" "Receive TTL must be optional for messages without one exact value"
assert_contains "$network_manager" "Result<MeshMessageReceiveResult, Error>" "NetworkManager metadata callback must carry receive results"
assert_contains "$mesh_api" "sendMessageWithReceiveMetadata" "MeshAPI must expose acknowledged send with receive metadata"
assert_contains "$mesh_api" "defaultTTL: defaultTTL" "Metadata-aware send must preserve the explicit App Tx TTL"

assert_contains "$replay_event" "public let receivedTTL: UInt8" "Replay rejected packet event must expose its Network PDU TTL"
assert_contains "$lower_transport" "receivedTTL: networkPdu\\.ttl" "Replay rejection must publish the rejected packet TTL"

assert_contains "$ack_tracker" "activeAppTxTTL = defaultTTL" "ACK tracker must capture App Tx TTL at send time"
assert_contains "$ack_tracker" "sendMessageWithReceiveMetadata" "ACK tracker must use the metadata-aware receive path"
assert_contains "$ack_tracker" "responseResult\\.receivedTTL" "Normal ACK result must read ACK Rx TTL"
assert_contains "$ack_tracker" "diagnostic\\.receivedTTL" "Replay rejected result must read packet Rx TTL"
assert_contains "$ack_tracker" "activeAppTxTTL = nil" "ACK tracker must clear the captured Tx TTL after completion"

result_line=$(rg -n 'light_ack_result_ok_format' "$ack_tracker" | head -1 | cut -d: -f1)
ttl_line=$(rg -n 'activeLines\.append\(ttlLine' "$ack_tracker" | head -1 | cut -d: -f1)
response_line=$(rg -n 'light_ack_response_format' "$ack_tracker" | head -1 | cut -d: -f1)
if [[ -z "$result_line" || -z "$ttl_line" || -z "$response_line" ||
      "$result_line" -ge "$ttl_line" || "$ttl_line" -ge "$response_line" ]]; then
  echo "FAIL: TTL detail must be rendered after Result and before Response"
  exit 1
fi

assert_contains_fixed "$en_strings" '"light_ack_ttl_format" = "ACK Rx TTL %d (App Tx TTL %d)";' "English TTL diagnostic wording must match the approved UI copy"
assert_contains_fixed "$zh_strings" '"light_ack_ttl_format" = "ACK 接收 TTL %d（App 发送 TTL %d）";' "Simplified Chinese TTL diagnostic must be localized"

while IFS= read -r file; do
  case "$file" in
    "$ack_tracker"|"SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift"|"SunSmart/Main/Device/Controller/DeviceLightViewController.swift")
      ;;
    *)
      echo "FAIL: Light ACK details must not be newly wired outside the existing Light entry points"
      echo "  file: $file"
      exit 1
      ;;
  esac
done < <(rg -l "LightAckProgressTracker" SunSmart --glob '*.swift')

echo "PASS: Light ACK receive/App transmit TTL contract"
