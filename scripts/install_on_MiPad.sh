#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf '用法：%s [Debug|Release]\n默认构建 Debug，随后安装到 MiPAD 并启动。\n' "$0"
}

if [[ $# -gt 1 ]]; then
    usage >&2
    exit 2
fi

configuration="${1:-Debug}"
case "$configuration" in
    Debug|Release) ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
device_id="00008103-001E29400CE9401E"
derived_data="/tmp/SunSmart-$(basename "$project_root")-MiPAD"
app_path="$derived_data/Build/Products/$configuration-iphoneos/SunSmart.app"

cd "$project_root"
if [[ -d SunSmartLocal.xcworkspace ]]; then
    workspace="SunSmartLocal.xcworkspace"
elif [[ -d SunSmart.xcworkspace ]]; then
    workspace="SunSmart.xcworkspace"
else
    printf '错误：%s 中未找到 SunSmartLocal.xcworkspace 或 SunSmart.xcworkspace。\n' "$project_root" >&2
    exit 1
fi

printf '构建 %s：%s/%s\n请保持 MiPAD 连接并解锁。\n' "$configuration" "$project_root" "$workspace"

# 真机安装必须保留签名，沿用工程已有签名配置。
xcodebuild \
    -workspace "$workspace" \
    -scheme SunSmart \
    -configuration "$configuration" \
    -sdk iphoneos \
    -destination "platform=iOS,id=$device_id" \
    -derivedDataPath "$derived_data" \
    -allowProvisioningUpdates \
    build

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Info.plist")"

printf '安装到 MiPAD：%s\n' "$app_path"
xcrun devicectl device install app --device "$device_id" "$app_path"

printf '启动：%s\n' "$bundle_id"
xcrun devicectl device process launch \
    --device "$device_id" \
    --terminate-existing \
    "$bundle_id"

printf '完成：%s 已安装到 MiPAD 并启动。\n' "$configuration"
