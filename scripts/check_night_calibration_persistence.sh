#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
test_binary="${TMPDIR:-/tmp}/NightCalibrationPersistenceContractTests"

swiftc -parse-as-library \
    "$repo_root/Tests/Group/NightCalibrationPersistenceContractTests.swift" \
    -o "$test_binary"

"$test_binary" \
    "$repo_root/SunSmart/Main/Profile/Model/Profile.swift" \
    "$repo_root/SunSmart/Common/Data/Database.swift" \
    "$repo_root/SunSmart/Common/Data/ExportData.swift" \
    "$repo_root/SunSmart/Common/Data/ImportData.swift"
