#!/usr/bin/env bash
set -euo pipefail

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

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if rg -q "$pattern" "$file"; then
    echo "FAIL: $message"
    echo "  file: $file"
    echo "  unexpected pattern: $pattern"
    exit 1
  fi
}

group_file="SunSmart/Main/Group/Controller/GroupViewController.swift"
sensor_file="SunSmart/Main/Group/View/GroupSensorView.swift"

assert_contains "$group_file" "refreshUIInterval[[:space:]]*:[[:space:]]*TimeInterval[[:space:]]*=[[:space:]]*1" "Group page must define a 1-second UI refresh interval"
assert_contains "$group_file" "pendingDeviceRefreshAddresses" "Group page must track dirty device addresses"
assert_contains "$group_file" "pendingSensorRefreshEvents" "Group page must track dirty sensor events"
assert_contains "$group_file" "isDeviceCollectionScrolling" "Group page must gate device UI refresh while collection view scrolls"
assert_contains "$group_file" "isSensorTableScrolling" "Group page must gate sensor UI refresh while sensor table scrolls"
assert_contains "$group_file" "startUIRefreshTimer" "Group page must start a scheduled UI refresh timer"
assert_contains "$group_file" "stopUIRefreshTimer" "Group page must stop the scheduled UI refresh timer"
assert_contains "$group_file" "flushPendingUIUpdates" "Group page must flush pending UI updates through one coordinator"
assert_contains "$group_file" "flushPendingUIUpdatesImmediately" "Group page must support immediate flush for user interactions and scroll end"
assert_contains "$group_file" "deferNextScheduledUIFlush" "Immediate UI flush must defer the next scheduled flush"
assert_contains "$group_file" "markDeviceDirty" "Device updates must be recorded as dirty state"
assert_contains "$group_file" "markSensorDirty" "Sensor updates must be recorded as dirty state"
assert_contains "$group_file" "scrollViewWillBeginDragging" "Collection view drag start must set scrolling state"
assert_contains "$group_file" "scrollViewDidEndDragging" "Collection view drag end must flush pending state"
assert_contains "$group_file" "sensorViewDidBeginScrolling" "Sensor table drag start must reach the controller"
assert_contains "$group_file" "sensorViewDidEndScrolling" "Sensor table drag end must flush pending state"
assert_not_contains "$group_file" "sensorView\\?\\.reloadSensorData\\(sensor:" "Mesh message handling must not directly refresh one sensor row"

assert_contains "$sensor_file" "struct SensorRefreshEvent" "GroupSensorView must expose a batched sensor refresh event"
assert_contains "$sensor_file" "reloadSensorData\\(events:" "GroupSensorView must support batched sensor refresh"
assert_contains "$sensor_file" "isTransientPresenceTrigger" "Transient proximity trigger state must survive delayed UI flush"
assert_contains "$sensor_file" "sensorViewDidBeginScrolling" "GroupSensorView must notify table scroll start"
assert_contains "$sensor_file" "sensorViewDidEndScrolling" "GroupSensorView must notify table scroll end"
assert_contains "$sensor_file" "scrollViewWillBeginDragging" "Sensor table drag start must be observed"
assert_contains "$sensor_file" "scrollViewDidEndDragging" "Sensor table drag end must be observed"
assert_contains "$sensor_file" "scrollViewDidEndDecelerating" "Sensor table deceleration end must be observed"

echo "PASS: Group page UI refresh coalescing contract"
