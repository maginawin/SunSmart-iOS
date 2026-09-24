#!/bin/sh
set -eu

# Xcode Cloud starts this script in ci_scripts; Podfile is one directory above.
cd "$(dirname "$0")/.."

# Allow CocoaPods version metadata to follow the tool installed on Xcode Cloud.
pod install
