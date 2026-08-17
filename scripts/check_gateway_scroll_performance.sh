#!/usr/bin/env bash
set -euo pipefail

swiftc -parse-as-library \
  Tests/Device/GatewayScrollPerformanceContractTests.swift \
  -o /tmp/GatewayScrollPerformanceContractTests

/tmp/GatewayScrollPerformanceContractTests \
  SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift \
  SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift \
  SunSmart/Main/Device/Gateway/View/GatewayInformationHeaderView.swift \
  SunSmart/Main/Device/Gateway/View/GatewayNetworkConnectivityCell.swift \
  SunSmart/Main/Device/Gateway/Model/GatewayDetailClockCoordinator.swift
