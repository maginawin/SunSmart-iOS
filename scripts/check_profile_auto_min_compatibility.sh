#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
test_binary="${TMPDIR:-/tmp}/ProfileAutoMinCompatibilityContractTests"

swiftc -parse-as-library \
    "$repo_root/Tests/Group/ProfileAutoMinCompatibilityContractTests.swift" \
    -o "$test_binary"

"$test_binary" \
    "$repo_root/SunSmart/Main/Profile/Model/Profile.swift" \
    "$repo_root/SunSmart/Common/Data/ImportData.swift" \
    "$repo_root/SunSmart/Common/Data/Database.swift" \
    "$repo_root/SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift" \
    "$repo_root/SunSmart/Common/Data/Node+SyncData.swift"
