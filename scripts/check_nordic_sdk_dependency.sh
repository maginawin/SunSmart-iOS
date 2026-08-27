#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
app_root="$(cd "$script_dir/.." && pwd)"
project_file="$app_root/SunSmart.xcodeproj/project.pbxproj"
workspace_file="$app_root/SunSmart.xcworkspace/contents.xcworkspacedata"
resolved_file="$app_root/SunSmart.xcworkspace/xcshareddata/swiftpm/Package.resolved"
ignore_file="$app_root/.gitignore"
package_id="C8D5314A2F76294A0069C71B"
repository_url="git@gitee.com:sunricher-i-os/nordic-sig-mesh-sdk.git"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

grep -Fq "isa = XCRemoteSwiftPackageReference;" "$project_file" || \
  fail "NordicSigMeshSDK must use a remote Swift Package reference."

if grep -Eiq 'XCLocalSwiftPackageReference[^;]*(nordic-sig-mesh-sdk|NordicSigMeshSDK)' "$project_file"; then
  fail "NordicSigMeshSDK local Package reference must not enter the shared project."
fi

if grep -Eiq '/Users/[^;\"]*/nordic-sig-mesh-sdk' "$project_file"; then
  fail "A developer-specific NordicSigMeshSDK path was found in the shared project."
fi

if grep -Eiq '(nordic-sig-mesh-sdk-worktrees/one-dev|/Users/[^\"]*/nordic-sig-mesh-sdk)' "$workspace_file"; then
  fail "A developer-specific NordicSigMeshSDK override was found in the shared workspace."
fi

grep -Fq "repositoryURL = \"$repository_url\";" "$project_file" || \
  fail "NordicSigMeshSDK repository URL is incorrect."
grep -Fq "branch = release;" "$project_file" || \
  fail "NordicSigMeshSDK must follow the release branch."

product_dependency_count="$(grep -Fc "package = $package_id" "$project_file")"
[[ "$product_dependency_count" == "4" ]] || \
  fail "Expected four App targets to link NordicSigMeshSDK; found $product_dependency_count."

[[ -f "$resolved_file" ]] || fail "Shared Package.resolved is missing."
grep -Fq '"identity" : "nordic-sig-mesh-sdk"' "$resolved_file" || \
  fail "Package.resolved does not contain NordicSigMeshSDK."
grep -Fq "\"location\" : \"$repository_url\"" "$resolved_file" || \
  fail "Package.resolved repository URL is incorrect."
grep -Fq '"branch" : "release"' "$resolved_file" || \
  fail "Package.resolved does not record the release branch."

grep -Fxq 'SunSmartLocal.xcworkspace/' "$ignore_file" || \
  fail "Developer-local workspace must be ignored."
grep -Fxq '.local-sdk/' "$ignore_file" || \
  fail "Developer-local SDK alias must be ignored."

if git -C "$app_root" ls-files --error-unmatch SunSmartLocal.xcworkspace >/dev/null 2>&1; then
  fail "Developer-local workspace must not be tracked."
fi

if git -C "$app_root" ls-files --error-unmatch .local-sdk >/dev/null 2>&1; then
  fail "Developer-local SDK alias must not be tracked."
fi

echo "PASS: NordicSigMeshSDK shared dependency configuration is valid."
