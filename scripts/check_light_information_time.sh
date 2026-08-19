#!/usr/bin/env bash
set -euo pipefail

coordinator="SunSmart/Main/Device/Lights/Model/LightTimeInformationCoordinator.swift"
sdk_manager="/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift"

swiftc -parse-as-library \
  "$coordinator" \
  Tests/Device/LightTimeInformationPolicyTests.swift \
  -o /tmp/LightTimeInformationPolicyTests
/tmp/LightTimeInformationPolicyTests

swiftc -parse-as-library \
  Tests/Device/LightTimeInformationRuntimeContractTests.swift \
  -o /tmp/LightTimeInformationRuntimeContractTests
/tmp/LightTimeInformationRuntimeContractTests \
  "$coordinator" \
  SunSmart/Main/Device/Controller/DeviceLightViewController.swift \
  SunSmart/Main/Device/Controller/DeviceInformationViewController.swift \
  "$sdk_manager" \
  SunSmart.xcodeproj/project.pbxproj

bash scripts/check_gateway_information_time.sh
plutil -lint SunSmart.xcodeproj/project.pbxproj
git diff --check

printf 'PASS: Light Information time checks completed.\n'
