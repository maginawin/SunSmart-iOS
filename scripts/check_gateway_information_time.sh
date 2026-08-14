#!/usr/bin/env bash
set -euo pipefail

coordinator="SunSmart/Main/Device/Gateway/Model/GatewayTimeInformationCoordinator.swift"
project="SunSmart.xcodeproj/project.pbxproj"

swiftc -parse-as-library \
  "$coordinator" \
  Tests/Device/GatewayTimeInformationCoordinatorTests.swift \
  -o /tmp/GatewayTimeInformationCoordinatorTests
/tmp/GatewayTimeInformationCoordinatorTests

swiftc -parse-as-library \
  Tests/Device/GatewayTimeInformationRuntimeContractTests.swift \
  -o /tmp/GatewayTimeInformationRuntimeContractTests
/tmp/GatewayTimeInformationRuntimeContractTests "$coordinator" "$project"

swiftc -parse-as-library \
  Tests/Device/GatewayInformationTimeRowsContractTests.swift \
  -o /tmp/GatewayInformationTimeRowsContractTests
/tmp/GatewayInformationTimeRowsContractTests \
  SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift \
  SunSmart/Main/Device/Controller/DeviceInformationViewController.swift \
  SunSmart/en.lproj/Localizable.strings \
  SunSmart/zh-Hans.lproj/Localizable.strings

swiftc -parse-as-library \
  SunSmart/Main/Site/Model/GatewayFastAddTimeInitialization.swift \
  Tests/Site/GatewayFastAddTimeInitializationTests.swift \
  -o /tmp/GatewayFastAddTimeInitializationTests
/tmp/GatewayFastAddTimeInitializationTests

swiftc -parse-as-library \
  Tests/Site/GatewayFastAddTimeInitializationContractTests.swift \
  -o /tmp/GatewayFastAddTimeInitializationContractTests
/tmp/GatewayFastAddTimeInitializationContractTests \
  SunSmart/Main/Site/Model/GatewayFastAddTimeInitialization.swift \
  SunSmart/Main/Site/Controller/SiteDeviceAddViewController.swift \
  SunSmart/Common/Data/ExportData.swift \
  "$project"

swiftc -parse-as-library \
  SunSmart/Main/Device/Gateway/Model/WiFiGatewayAutomaticLoadGate.swift \
  Tests/Device/WiFiGatewayAutomaticLoadGateTests.swift \
  -o /tmp/WiFiGatewayAutomaticLoadGateTests
/tmp/WiFiGatewayAutomaticLoadGateTests

bash scripts/check_wifi_gateway_proxy_ready_no_time_set.sh

plutil -lint SunSmart/en.lproj/Localizable.strings
plutil -lint SunSmart/zh-Hans.lproj/Localizable.strings

printf 'PASS: Gateway Information time checks completed.\n'
