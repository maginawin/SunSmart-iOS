#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
app_root="$(cd "$script_dir/.." && pwd)"
default_sdk_root="$(cd "$app_root/../.." && pwd)/nordic-sig-mesh-sdk-worktrees/one-dev"
sdk_root="${1:-${NORDIC_SIG_MESH_SDK_ROOT:-$default_sdk_root}}"
local_sdk_dir="$app_root/.local-sdk"
local_sdk_alias="$local_sdk_dir/nordic-sig-mesh-sdk"
local_workspace="$app_root/SunSmartLocal.xcworkspace"
workspace_file="$local_workspace/contents.xcworkspacedata"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[[ -f "$sdk_root/Package.swift" ]] || \
  fail "NordicSigMeshSDK Package.swift not found at: $sdk_root"

sdk_root="$(cd "$sdk_root" && pwd -P)"

git -C "$sdk_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || \
  fail "NordicSigMeshSDK path is not a Git worktree: $sdk_root"

"$script_dir/check_nordic_sdk_dependency.sh"

mkdir -p "$local_sdk_dir" "$local_workspace"

if [[ -L "$local_sdk_alias" ]]; then
  current_target="$(readlink "$local_sdk_alias")"
  [[ "$current_target" == "$sdk_root" ]] || \
    fail "Existing SDK alias points to '$current_target', expected '$sdk_root'. Remove the ignored alias explicitly, then run again."
elif [[ -e "$local_sdk_alias" ]]; then
  fail "Local SDK alias path already exists and is not a symlink: $local_sdk_alias"
else
  ln -s "$sdk_root" "$local_sdk_alias"
fi

workspace_temp="$(mktemp "$local_workspace/contents.xcworkspacedata.XXXXXX")"
trap 'rm -f "$workspace_temp"' EXIT

{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<Workspace'
  echo '   version = "1.0">'
  echo '   <FileRef'
  echo '      location = "group:SunSmart.xcodeproj">'
  echo '   </FileRef>'
  echo '   <FileRef'
  echo '      location = "group:Pods/Pods.xcodeproj">'
  echo '   </FileRef>'
  echo '   <FileRef'
  echo '      location = "group:.local-sdk/nordic-sig-mesh-sdk">'
  echo '   </FileRef>'
  echo '</Workspace>'
} > "$workspace_temp"

mv "$workspace_temp" "$workspace_file"
chmod 644 "$workspace_file"
trap - EXIT

sdk_branch="$(git -C "$sdk_root" branch --show-current)"
sdk_head="$(git -C "$sdk_root" rev-parse HEAD)"

echo "PASS: Local NordicSigMeshSDK workspace is ready."
echo "Workspace: $local_workspace"
echo "SDK root: $sdk_root"
echo "SDK branch: ${sdk_branch:-DETACHED}"
echo "SDK HEAD: $sdk_head"
