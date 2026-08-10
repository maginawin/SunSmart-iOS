#!/bin/sh

set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_BINARY=/tmp/device_restore_transition_time_policy_tests

cleanup() {
    rm -f "$TEST_BINARY"
}
trap cleanup EXIT

cd "$PROJECT_DIR"

xcrun swiftc \
    SunSmart/Common/Data/DeviceRestoreDefaultTransitionTimePolicy.swift \
    scripts/tests/DeviceRestoreDefaultTransitionTimePolicyTests.swift \
    -o "$TEST_BINARY"
"$TEST_BINARY"

require_fixed() {
    pattern=$1
    file=$2
    if ! grep -Fq "$pattern" "$file"; then
        echo "FAIL: missing wiring '$pattern' in $file" >&2
        exit 1
    fi
}

require_count() {
    expected=$1
    pattern=$2
    file=$3
    actual=$(grep -cF "$pattern" "$file" || true)
    if [ "$actual" -ne "$expected" ]; then
        echo "FAIL: expected $expected occurrences of '$pattern' in $file, found $actual" >&2
        exit 1
    fi
}

require_fixed \
    "defaultTransitionTime: oldNode.defaultTransitionTime" \
    SunSmart/Common/Data/MeshNetwork+SunSmart.swift
require_count \
    2 \
    "DeviceRestoreDefaultTransitionTimePolicy.pendingTargetRawValue(" \
    SunSmart/Common/Data/Node+SyncData.swift
require_fixed \
    "deviceParameterTypes.append(.defaultTransitionTime(transitionTime: .init(rawValue: targetRawValue)))" \
    SunSmart/Common/Data/Node+SyncData.swift
require_fixed \
    "GenericDefaultTransitionTimeSet(transitionTime: transitionTime)" \
    SunSmart/Common/Data/Node+SyncData.swift
require_fixed \
    "return node.defaultTransitionTime?.rawValue == transitionTime.rawValue" \
    SunSmart/Main/Space/Model/SyncDevicesCellModel.swift
require_fixed \
    "case is GenericDefaultTransitionTimeSet:" \
    SunSmart/Common/Data/MeshNetwork+SunSmart.swift
require_fixed \
    "DeviceRestoreDefaultTransitionTimePolicy.shouldClearRestoreTarget(" \
    SunSmart/Common/Data/MeshNetwork+SunSmart.swift
require_fixed \
    "successfulSetRawValue: transitionTimeMessage.transitionTime.rawValue" \
    SunSmart/Common/Data/MeshNetwork+SunSmart.swift
require_fixed \
    "self.restoreData?.defaultTransitionTime = nil" \
    SunSmart/Common/Data/MeshNetwork+SunSmart.swift
require_fixed \
    "            self.restoreData?.defaultTransitionTime = nil
            save()" \
    SunSmart/Common/Data/MeshNetwork+SunSmart.swift

echo "PASS: default transition time restore wiring contracts"
