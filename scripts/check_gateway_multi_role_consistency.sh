#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

swiftc -parse-as-library \
  SunSmart/Main/Device/Gateway/Model/GatewayCloudSyncGenerationPolicy.swift \
  Tests/Device/GatewayCloudSyncGenerationPolicyTests.swift \
  -o /tmp/GatewayCloudSyncGenerationPolicyTests
/tmp/GatewayCloudSyncGenerationPolicyTests

swiftc -parse-as-library \
  SunSmart/Main/Device/Gateway/Model/GatewayAssociatedSpaceCandidatePolicy.swift \
  Tests/Device/GatewayAssociatedSpaceCandidatePolicyTests.swift \
  -o /tmp/GatewayAssociatedSpaceCandidatePolicyTests
/tmp/GatewayAssociatedSpaceCandidatePolicyTests

swiftc -parse-as-library \
  Tests/Device/GatewayMultiRoleConsistencyContractTests.swift \
  -o /tmp/GatewayMultiRoleConsistencyContractTests
/tmp/GatewayMultiRoleConsistencyContractTests \
  SunSmart/Common/Data/ImportData.swift \
  SunSmart/Common/Data/Database.swift \
  SunSmart/Main/Device/Gateway/Model/GatewayModel.swift \
  SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift \
  SunSmart/Main/Device/Gateway/Controller/GatewayAssociatedSpacesController.swift \
  SunSmart/Common/Data/Node+SyncData.swift \
  SunSmart/Common/Cloud/CloudSynchronizationManager.swift \
  SunSmart/en.lproj/Localizable.strings \
  SunSmart/zh-Hans.lproj/Localizable.strings

echo "PASS: Gateway multi-role consistency checks passed."
