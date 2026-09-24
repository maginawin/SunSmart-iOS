#!/bin/sh
set -eu

# Xcode Cloud starts this script in ci_scripts, while Podfile is at the repository root.
if [ -n "${CI_PRIMARY_REPOSITORY_PATH:-}" ]; then
  cd "$CI_PRIMARY_REPOSITORY_PATH"
else
  cd "$(dirname "$0")/.."
fi

# Recreate all Pods support files without changing the locked dependency versions.
pod install --deployment
