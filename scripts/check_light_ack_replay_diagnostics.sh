#!/usr/bin/env bash
set -euo pipefail

sdk_root="${NORDIC_SIG_MESH_SDK_ROOT:-/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk}"
event_file="$sdk_root/Sources/NordicSigMeshSDK/MeshLib/Diagnostics/MeshReplayProtectionDiscardEvent.swift"
network_manager_file="$sdk_root/Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/NetworkManager.swift"
lower_transport_file="$sdk_root/Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/Lower Transport Layer/LowerTransportLayer.swift"
ack_file="SunSmart/Main/Device/Lights/Model/LightAckProgressTracker.swift"
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

test -f "$event_file" || {
  echo "FAIL: replay protection diagnostic event type is missing"
  echo "  file: $event_file"
  exit 1
}

assert_contains "$event_file" "struct MeshReplayProtectionDiscardEvent" "SDK must expose replay discard event data"
assert_contains "$event_file" "meshReplayProtectionDiscarded" "SDK must expose replay discard notification name"
assert_contains "$event_file" "pendingResponseOpCode" "Replay event must include pending acknowledged response opcode"
assert_contains "$event_file" "pendingMessageOpCode" "Replay event must include pending message callback opcode"
assert_contains "$network_manager_file" "notifyAboutReplayProtectionDiscard" "NetworkManager must publish replay discard diagnostics"
assert_contains "$network_manager_file" "MeshReplayProtectionDiscardEvent" "NetworkManager must build replay discard event objects"
assert_contains "$lower_transport_file" "notifyAboutReplayProtectionDiscard" "LowerTransportLayer must publish diagnostics when replay protection rejects a packet"

assert_contains "$ack_file" "meshReplayProtectionDiscarded" "ACK tracker must observe replay discard diagnostics"
assert_contains "$ack_file" "MeshReplayProtectionDiscardEvent" "ACK tracker must parse replay discard events"
assert_contains "$ack_file" "activeReplayDiagnostic" "ACK tracker must remember replay rejection while waiting for ACK"
assert_contains "$ack_file" "light_ack_result_replay_rejected_format" "ACK tracker must display replay rejected result"
assert_contains "$ack_file" "light_ack_replay_detail_format" "ACK tracker must display replay rejection details"

assert_contains "$en_strings" "light_ack_result_replay_rejected_format" "English strings must include replay rejected result"
assert_contains "$en_strings" "light_ack_replay_detail_format" "English strings must include replay rejected details"
assert_contains "$zh_strings" "light_ack_result_replay_rejected_format" "Simplified Chinese strings must include replay rejected result"
assert_contains "$zh_strings" "light_ack_replay_detail_format" "Simplified Chinese strings must include replay rejected details"

echo "PASS: Light ACK replay diagnostics contract"
