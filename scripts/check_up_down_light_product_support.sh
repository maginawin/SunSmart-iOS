#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
temporary_dir="$(mktemp -d /tmp/up-down-light-product-support.XXXXXX)"
test_binary="/tmp/UpDownLightProductSupportContractTests"

cleanup() {
  rm -rf "${temporary_dir}"
}
trap cleanup EXIT

swiftc \
  -parse-as-library \
  -emit-module \
  -emit-object \
  -module-name NordicSigMeshSDK \
  "${repo_root}/Tests/Device/UpDownLightNordicSigMeshSDKStub.swift" \
  -emit-module-path "${temporary_dir}/NordicSigMeshSDK.swiftmodule" \
  -o "${temporary_dir}/NordicSigMeshSDK.o"

swiftc \
  -parse-as-library \
  -I "${temporary_dir}" \
  "${repo_root}/SunSmart/Common/Data/Node+Capability.swift" \
  "${repo_root}/Tests/Device/UpDownLightProductSupportContractTests.swift" \
  "${temporary_dir}/NordicSigMeshSDK.o" \
  -o "${test_binary}"

"${test_binary}" "${repo_root}"
