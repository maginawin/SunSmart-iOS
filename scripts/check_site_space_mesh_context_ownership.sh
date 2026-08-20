#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
test_source="${repo_root}/Tests/Site/SiteSpaceMeshContextOwnershipContractTests.swift"
site_source="${repo_root}/SunSmart/Main/Site/Controller/SiteViewController.swift"
space_source="${repo_root}/SunSmart/Main/Space/Controller/SpaceViewController.swift"
import_source="${repo_root}/SunSmart/Common/Data/ImportData.swift"
temp_dir="$(mktemp -d)"
test_binary="${temp_dir}/site_space_mesh_context_ownership_contract_tests"

cleanup() {
  rm -rf "${temp_dir}"
}
trap cleanup EXIT

swiftc -parse-as-library \
  "${test_source}" \
  -o "${test_binary}"

"${test_binary}" \
  "${site_source}" \
  "${space_source}" \
  "${import_source}"

echo "PASS: Site and Space Mesh context ownership checks passed."
