#!/usr/bin/env bash

resolve_nordic_sdk_root() {
  local app_root="$1"
  local explicit_root="${2:-${NORDIC_SIG_MESH_SDK_ROOT:-}}"
  local one_dev_root="${app_root}/../../nordic-sig-mesh-sdk-worktrees/one-dev"
  local selected_root=""

  if [[ -n "$explicit_root" ]]; then
    selected_root="$explicit_root"
  elif [[ -d "$one_dev_root" ]]; then
    selected_root="$one_dev_root"
  else
    echo "FAIL: NordicSigMeshSDK source checkout was not found." >&2
    echo "  Pass the SDK root as the script argument or set NORDIC_SIG_MESH_SDK_ROOT." >&2
    return 1
  fi

  if [[ ! -f "$selected_root/Package.swift" ]]; then
    echo "FAIL: NordicSigMeshSDK root does not contain Package.swift." >&2
    echo "  path: $selected_root" >&2
    return 1
  fi

  (cd "$selected_root" && pwd)
}
