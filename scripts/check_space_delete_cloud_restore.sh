#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SPACE_FILE="$ROOT_DIR/SunSmart/Main/Space/Controller/SpaceViewController.swift"
LIGHTS_FILE="$ROOT_DIR/SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift"
SWITCHES_FILE="$ROOT_DIR/SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift"
OTHERS_FILE="$ROOT_DIR/SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift"
SENSORS_FILE="$ROOT_DIR/SunSmart/Main/Device/Sensors/Controller/DeviceSensorsViewController.swift"

assert_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if ! grep -Fq "$pattern" "$file"; then
    echo "FAIL: $message" >&2
    echo "Missing pattern: $pattern" >&2
    echo "File: $file" >&2
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if grep -Fq "$pattern" "$file"; then
    echo "FAIL: $message" >&2
    echo "Unexpected pattern: $pattern" >&2
    echo "File: $file" >&2
    exit 1
  fi
}

assert_contains "$SPACE_FILE" "func commitLocalChangeForCloudSync(site currentSite: SiteData? = nil, changeType: SpaceChangeDataType)" \
  "SpaceData must expose a shared local-change cloud commit helper."
assert_contains "$SPACE_FILE" "lastUpdate = max(now, lastUpdate + 1, (lastUploadCloudTimestamp ?? 0) + 1)" \
  "Space dirty timestamp must become newer than the last upload timestamp, even within the same second."
assert_contains "$SPACE_FILE" "site.spaces = SpaceData.load(siteId: site.id)" \
  "Loaded SiteData must restore its Spaces before fallback site sync."
assert_contains "$SPACE_FILE" "site.markSiteUploadNeededForSpaceAddressChange()" \
  "Address-changing deletes must also dirty the parent Site before syncSite."
assert_contains "$SPACE_FILE" "self.space.commitLocalChangeForCloudSync(site: self.site, changeType: type)" \
  "SpaceViewController notification observer must reuse the shared helper."

assert_contains "$LIGHTS_FILE" "self.space.commitLocalChangeForCloudSync(site: self.site, changeType: .network(type: .address))" \
  "Lights delete flow must directly mark Space dirty after local node deletion."
assert_not_contains "$LIGHTS_FILE" "NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.network(type: .address))" \
  "Lights delete flow must not rely on the Space data-changed notification for cloud dirtying."

assert_contains "$SWITCHES_FILE" "space.commitLocalChangeForCloudSync(changeType: .device)" \
  "Switches delete flow must directly mark Space dirty after deleting switch data."
assert_not_contains "$SWITCHES_FILE" "NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)" \
  "Switches delete flow must not rely on the Space data-changed notification for cloud dirtying."

assert_contains "$OTHERS_FILE" "space.commitLocalChangeForCloudSync(changeType: .network(type: .address))" \
  "Others delete flow must directly mark Space dirty after deleting node-backed items."
assert_not_contains "$OTHERS_FILE" "NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.network(type: .address))" \
  "Others delete flow must not rely on the Space data-changed notification for cloud dirtying."

assert_contains "$SENSORS_FILE" "collectionView.showEmptyDataView(title: \"no_sensors\".localizedString" \
  "Sensors page should remain an empty-state page with no delete flow in this task."

echo "PASS: Space delete cloud restore contracts hold."
