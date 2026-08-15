#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
test_binary="/tmp/SiteTimeSetMessageFactoryTests"
value_test_binary="/tmp/SiteTimeZoneValueTests"

swiftc -parse-as-library \
  "${repo_root}/SunSmart/Common/Data/SiteTimeZoneValue.swift" \
  "${repo_root}/SunSmart/Common/Data/SiteTimeSetMessageFactory.swift" \
  "${repo_root}/Tests/Site/SiteTimeSetMessageFactoryTests.swift" \
  -o "${test_binary}"

"${test_binary}"

swiftc -parse-as-library \
  "${repo_root}/SunSmart/Common/Data/SiteTimeZoneValue.swift" \
  "${repo_root}/Tests/Site/SiteTimeZoneValueTests.swift" \
  -o "${value_test_binary}"

"${value_test_binary}"
