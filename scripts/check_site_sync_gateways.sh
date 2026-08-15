#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

swiftc -parse-as-library \
  SunSmart/Main/Site/Model/SiteGatewayHeaderLayoutPolicy.swift \
  Tests/Site/SiteGatewayHeaderLayoutPolicyTests.swift \
  -o /tmp/SiteGatewayHeaderLayoutPolicyTests
/tmp/SiteGatewayHeaderLayoutPolicyTests

swiftc -parse-as-library \
  SunSmart/Common/Data/SiteTimeZoneValue.swift \
  SunSmart/Main/Site/Model/SitePropsEditPolicy.swift \
  SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift \
  SunSmart/Main/Site/Model/SiteGatewayAccessScope.swift \
  SunSmart/Main/Site/Model/SyncGatewaysContext.swift \
  Tests/Site/SyncGatewaysContextTests.swift \
  -o /tmp/SyncGatewaysContextTests
/tmp/SyncGatewaysContextTests

swiftc -parse-as-library \
  Tests/Site/SiteGatewayTimeZoneNameColorContractTests.swift \
  -o /tmp/SiteGatewayTimeZoneNameColorContractTests
/tmp/SiteGatewayTimeZoneNameColorContractTests \
  SunSmart/Main/Site/Model/SyncGatewaysContext.swift \
  SunSmart/Main/Site/View/GatewayListView.swift \
  SunSmart/Main/Site/View/SiteGatewaysMenuView.swift \
  SunSmart/Main/Site/Controller/SiteViewController.swift

swiftc -parse-as-library \
  SunSmart/Common/Data/SiteTimeZoneValue.swift \
  SunSmart/Main/Site/Model/SitePropsEditPolicy.swift \
  SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift \
  SunSmart/Main/Site/Model/SiteGatewayAccessScope.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneTarget.swift \
  SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift \
  Tests/Site/SiteEntryTimeZoneSyncPolicyTests.swift \
  -o /tmp/SyncGatewaysEntryPolicyTests
/tmp/SyncGatewaysEntryPolicyTests

swiftc -parse-as-library \
  SunSmart/Common/Data/SiteTimeZoneValue.swift \
  SunSmart/Main/Site/Model/SitePropsEditPolicy.swift \
  SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift \
  SunSmart/Main/Site/Model/SiteGatewayAccessScope.swift \
  SunSmart/Main/Site/Model/SyncGatewaysContext.swift \
  SunSmart/Main/Site/Model/SyncGatewaysState.swift \
  Tests/Site/SyncGatewaysStateTests.swift \
  -o /tmp/SyncGatewaysStateTests
/tmp/SyncGatewaysStateTests

swiftc -parse-as-library \
  SunSmart/Main/Site/Model/SyncGatewaysScanSession.swift \
  Tests/Site/SyncGatewaysScanSessionTests.swift \
  -o /tmp/SyncGatewaysScanSessionTests
/tmp/SyncGatewaysScanSessionTests

swiftc -parse-as-library \
  SunSmart/Main/Site/Model/GatewayTimeSyncCoordinator.swift \
  Tests/Site/GatewayTimeSyncCoordinatorTests.swift \
  -o /tmp/SyncGatewaysTimeCoordinatorTests
/tmp/SyncGatewaysTimeCoordinatorTests

swiftc -parse-as-library \
  SunSmart/Main/Device/Gateway/Model/GatewayCloudSyncGenerationPolicy.swift \
  Tests/Device/GatewayCloudSyncGenerationPolicyTests.swift \
  -o /tmp/SyncGatewaysCloudGenerationTests
/tmp/SyncGatewaysCloudGenerationTests

swiftc -parse-as-library \
  SunSmart/Main/Device/Gateway/Model/GatewayCloudSyncGenerationPolicy.swift \
  SunSmart/Main/Site/Model/SyncGatewaysDirtyTimeOverride.swift \
  SunSmart/Main/Site/Model/SyncGatewaysCloudBridge.swift \
  Tests/Site/SyncGatewaysCloudBridgeTests.swift \
  -o /tmp/SyncGatewaysCloudBridgeTests
/tmp/SyncGatewaysCloudBridgeTests

swiftc -parse-as-library \
  SunSmart/Common/Data/SiteTimeZoneValue.swift \
  SunSmart/Main/Site/Model/SitePropsEditPolicy.swift \
  SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift \
  SunSmart/Main/Site/Model/SiteGatewayAccessScope.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneTarget.swift \
  Tests/Site/SiteGatewayCloudTimeZoneTargetTests.swift \
  -o /tmp/SiteGatewayCloudTimeZoneTargetTests
/tmp/SiteGatewayCloudTimeZoneTargetTests

swiftc -parse-as-library \
  SunSmart/Common/Data/SiteTimeZoneValue.swift \
  SunSmart/Main/Site/Model/SitePropsEditPolicy.swift \
  SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift \
  SunSmart/Main/Site/Model/SiteGatewayAccessScope.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneTarget.swift \
  Tests/Site/SiteGatewayLocalTimeZoneTargetTests.swift \
  -o /tmp/SiteGatewayLocalTimeZoneTargetTests
/tmp/SiteGatewayLocalTimeZoneTargetTests

swiftc -parse-as-library \
  Tests/Site/SiteGatewayLocalTimeZoneContextContractTests.swift \
  -o /tmp/SiteGatewayLocalTimeZoneContextContractTests
/tmp/SiteGatewayLocalTimeZoneContextContractTests \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneLocalContext.swift \
  SunSmart/Main/Device/Gateway/Model/GatewayModel.swift

swiftc -parse-as-library \
  SunSmart/Common/Data/SiteTimeZoneValue.swift \
  SunSmart/Main/Site/Model/SitePropsEditPolicy.swift \
  SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift \
  SunSmart/Main/Site/Model/SiteGatewayAccessScope.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneTarget.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneSyncState.swift \
  Tests/Site/SiteGatewayCloudTimeZoneSyncStateTests.swift \
  -o /tmp/SiteGatewayCloudTimeZoneSyncStateTests
/tmp/SiteGatewayCloudTimeZoneSyncStateTests

swiftc -parse-as-library \
  SunSmart/Common/Data/SiteTimeZoneValue.swift \
  SunSmart/Main/Site/Model/SitePropsEditPolicy.swift \
  SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift \
  SunSmart/Main/Site/Model/SiteGatewayAccessScope.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneTarget.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneSyncState.swift \
  SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift \
  SunSmart/Main/Site/Model/SiteTimeZoneSyncPresentationState.swift \
  Tests/Site/SiteTimeZoneSyncPresentationStateTests.swift \
  -o /tmp/SiteTimeZoneSyncPresentationStateTests
/tmp/SiteTimeZoneSyncPresentationStateTests

swiftc -parse-as-library \
  SunSmart/Common/Data/SiteTimeZoneValue.swift \
  SunSmart/Main/Site/Model/SitePropsEditPolicy.swift \
  SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift \
  SunSmart/Main/Site/Model/SiteGatewayAccessScope.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneTarget.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneSyncState.swift \
  SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift \
  SunSmart/Main/Site/Model/SiteTimeZoneSyncPresentationState.swift \
  Tests/Site/SiteTimeZoneSyncResultLayoutPolicyTests.swift \
  -o /tmp/SiteTimeZoneSyncResultLayoutPolicyTests
/tmp/SiteTimeZoneSyncResultLayoutPolicyTests

swiftc -parse-as-library \
  SunSmart/Common/Data/SiteTimeZoneValue.swift \
  SunSmart/Main/Site/Model/SitePropsEditPolicy.swift \
  SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift \
  SunSmart/Main/Site/Model/SiteGatewayAccessScope.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneTarget.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneSyncState.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneResponseParser.swift \
  Tests/Site/SiteGatewayCloudTimeZoneResponseParserTests.swift \
  -o /tmp/SiteGatewayCloudTimeZoneResponseParserTests
/tmp/SiteGatewayCloudTimeZoneResponseParserTests

swiftc -parse-as-library \
  SunSmart/Common/Data/SiteTimeZoneValue.swift \
  SunSmart/Main/Site/Model/SitePropsEditPolicy.swift \
  SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift \
  SunSmart/Main/Site/Model/SiteGatewayAccessScope.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneTarget.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneSyncState.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneSyncCoordinator.swift \
  Tests/Site/SiteGatewayCloudTimeZoneSyncCoordinatorTests.swift \
  -o /tmp/SiteGatewayCloudTimeZoneSyncCoordinatorTests
/tmp/SiteGatewayCloudTimeZoneSyncCoordinatorTests

swiftc -parse-as-library \
  SunSmart/Common/Data/SiteTimeZoneValue.swift \
  SunSmart/Main/Site/Model/SitePropsEditPolicy.swift \
  SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift \
  SunSmart/Main/Site/Model/SiteGatewayAccessScope.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneTarget.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneSyncState.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneSyncCoordinator.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneSessionCoordinator.swift \
  Tests/Site/SiteGatewayCloudTimeZoneSessionCoordinatorTests.swift \
  -o /tmp/SiteGatewayCloudTimeZoneSessionCoordinatorTests
/tmp/SiteGatewayCloudTimeZoneSessionCoordinatorTests

swiftc -parse-as-library \
  SunSmart/Common/Data/SiteTimeZoneValue.swift \
  SunSmart/Main/Site/Model/SitePropsEditPolicy.swift \
  SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift \
  SunSmart/Main/Site/Model/SiteGatewayAccessScope.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneTarget.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneSyncState.swift \
  SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift \
  SunSmart/Main/Site/Model/SiteTimeZoneSyncPresentationState.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneSyncCoordinator.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneSessionCoordinator.swift \
  SunSmart/Main/Site/Model/SiteTimeZoneEditSyncCoordinator.swift \
  Tests/Site/SiteTimeZoneEditSyncCoordinatorTests.swift \
  -o /tmp/SiteTimeZoneEditSyncCoordinatorTests
/tmp/SiteTimeZoneEditSyncCoordinatorTests

swiftc -parse-as-library \
  Tests/Site/SiteGatewayCloudTimeZoneAPIContractTests.swift \
  -o /tmp/SiteGatewayCloudTimeZoneAPIContractTests
/tmp/SiteGatewayCloudTimeZoneAPIContractTests \
  SunSmart/Common/Network/NetowrkReqeustApi.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneResponseParser.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneAPIClient.swift \
  SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneSyncCoordinator.swift

swiftc -parse-as-library \
  Tests/Site/SiteGatewayCloudTimeZoneUIContractTests.swift \
  -o /tmp/SiteGatewayCloudTimeZoneUIContractTests
/tmp/SiteGatewayCloudTimeZoneUIContractTests \
  SunSmart/Main/Site/View/SiteEntryGatewayTimeZoneStatusView.swift \
  SunSmart/en.lproj/Localizable.strings \
  SunSmart/zh-Hans.lproj/Localizable.strings

swiftc -parse-as-library \
  Tests/Site/SiteEntryTimeZoneSyncContractTests.swift \
  -o /tmp/SyncGatewaysEntryContractTests
/tmp/SyncGatewaysEntryContractTests \
  SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift \
  SunSmart/Main/Site/View/SiteTimeZoneSyncStatusView.swift \
  SunSmart/en.lproj/Localizable.strings \
  SunSmart/zh-Hans.lproj/Localizable.strings \
  SunSmart/Main/Site/Controller/SiteViewController.swift \
  SunSmart.xcodeproj/project.pbxproj \
  scripts/check_site_sync_gateways.sh \
  SunSmart/Assets.xcassets/Common/site_entry_sync_warning.imageset/Contents.json

swiftc -parse-as-library \
  Tests/Site/SiteTimeZoneReviewSyncContractTests.swift \
  -o /tmp/SyncGatewaysReviewContractTests
/tmp/SyncGatewaysReviewContractTests \
  SunSmart/Main/Site/View/SiteTimeZoneReviewSyncView.swift \
  SunSmart/Main/Site/View/SiteGatewayHeaderView.swift \
  SunSmart/Main/Site/Controller/SiteViewController.swift \
  SunSmart/Main/Site/Controller/SyncGatewaysViewController.swift \
  SunSmart/en.lproj/Localizable.strings \
  SunSmart/zh-Hans.lproj/Localizable.strings \
  SunSmart.xcodeproj/project.pbxproj \
  SunSmart/Assets.xcassets/Common/site_entry_sync_warning.imageset/Contents.json

swiftc -parse-as-library \
  Tests/Site/SyncGatewaysUIContractTests.swift \
  -o /tmp/SyncGatewaysUIContractTests
/tmp/SyncGatewaysUIContractTests \
  SunSmart/Main/Site/View/SyncGatewaysTimeZoneCardView.swift \
  SunSmart/Main/Site/View/SyncGatewayCell.swift \
  SunSmart/Main/Site/View/SyncGatewaysSupportingViews.swift \
  SunSmart/Main/Site/Controller/SyncGatewaysViewController.swift \
  SunSmart/Main/Site/Controller/SiteViewController.swift \
  SunSmart/en.lproj/Localizable.strings \
  SunSmart/zh-Hans.lproj/Localizable.strings \
  SunSmart.xcodeproj/project.pbxproj

swiftc -parse-as-library \
  Tests/Site/SiteTimeZoneUIContractTests.swift \
  -o /tmp/SyncGatewaysExistingTimeZoneUIContractTests
/tmp/SyncGatewaysExistingTimeZoneUIContractTests \
  SunSmart/Main/Site/Controller/SiteEditViewController.swift \
  SunSmart/Main/Site/Controller/SiteTimeZoneSelectionViewController.swift \
  SunSmart/Main/Site/View/SiteTimeZoneSelectionCell.swift \
  SunSmart/Main/Site/View/SiteTimeZoneSyncStatusView.swift \
  SunSmart/Main/Site/Controller/SitesViewController.swift \
  SunSmart/Main/Site/Controller/SiteViewController.swift
/tmp/SyncGatewaysExistingTimeZoneUIContractTests \
  SunSmart/en.lproj/Localizable.strings \
  SunSmart/zh-Hans.lproj/Localizable.strings \
  SunSmart.xcodeproj/project.pbxproj \
  SunSmart/all_utc_timezones.json

echo "SiteSyncGateways checks passed"
