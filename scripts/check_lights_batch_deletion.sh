#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d /tmp/lights-batch-delete.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library \
  "$repo_root/SunSmart/Common/Data/LightsBatchDeletionPlan.swift" \
  "$repo_root/SunSmart/Common/Data/LightsBatchDeletionExecutor.swift" \
  "$repo_root/Tests/Device/LightsBatchDeletionTests.swift" -o "$test_dir/tests"
"$test_dir/tests"

swiftc -parse-as-library \
  "$repo_root/.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Bearer/GATT/GattWriteReceiptQueue.swift" \
  "$repo_root/Tests/Device/GattWriteReceiptTests.swift" -o "$test_dir/gatt-tests"
"$test_dir/gatt-tests"

python3 "$repo_root/scripts/check_lights_batch_deletion_context.py"
