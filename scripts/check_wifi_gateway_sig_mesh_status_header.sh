#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

header_view="SunSmart/Main/Device/Gateway/View/GatewayInformationHeaderView.swift"
gateway_controller="SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift"
wifi_controller="SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift"
en_strings="SunSmart/en.lproj/Localizable.strings"
zh_strings="SunSmart/zh-Hans.lproj/Localizable.strings"

rg -n "final class GatewayHeaderStatusItemView" "$header_view" >/dev/null \
  || fail "GatewayInformationHeaderView must define a reusable status item view."

rg -n "func update\\(iconName: String, title: String\\?, status: String, iconSize: CGFloat\\)" "$header_view" >/dev/null \
  || fail "GatewayHeaderStatusItemView update API must accept a style-specific icon size."

rg -n "make.width.height.equalTo\\(iconSize\\)" "$header_view" >/dev/null \
  || fail "GatewayHeaderStatusItemView image size must use the iconSize passed by callers."

rg -n "var iconSize: CGFloat" "$header_view" >/dev/null \
  || fail "Gateway header state style must expose an icon size."

rg -n "return SCRYFrom\\(40\\)" "$header_view" >/dev/null \
  || fail "Default gateway icon size must remain 40."

rg -n "return 30" "$header_view" >/dev/null \
  || fail "SIG Mesh icon size must remain 30."

rg -n "enum GatewayHeaderStateStyle" "$header_view" >/dev/null \
  || fail "GatewayInformationHeaderView must expose a configurable status style."

rg -n "case sigMesh" "$header_view" >/dev/null \
  || fail "GatewayInformationHeaderView must support SIG Mesh status style."

rg -n 'var onlineImageName' "$header_view" >/dev/null \
  || fail "Gateway header state style must expose an online image name."

rg -n 'return "bluetooth_online"' "$header_view" >/dev/null \
  || fail "SIG Mesh online state must use bluetooth_online."

rg -n 'var offlineImageName' "$header_view" >/dev/null \
  || fail "Gateway header state style must expose an offline image name."

rg -n 'return "bluetooth_offline"' "$header_view" >/dev/null \
  || fail "SIG Mesh offline state must use bluetooth_offline."

rg -n 'return "sig_mesh".localizedString' "$header_view" >/dev/null \
  || fail "SIG Mesh title must use localized sig_mesh key."

rg -n 'make.bottom.equalTo\(statusLabel.snp.top\).offset\(SCRYFrom\(-6\)\)' "$header_view" >/dev/null \
  || fail "SIG Mesh icon bottom must be 6pt above the Online/Offline label."

rg -n 'make.left.equalTo\(statusLabel.snp.left\).offset\(SCRXFrom\(-8\)\)' "$header_view" >/dev/null \
  || fail "SIG Mesh icon left must be 8pt to the left of the Online/Offline label left edge."

rg -n 'make.left.equalTo\(iconImageView.snp.right\).offset\(SCRXFrom\(2\)\)' "$header_view" >/dev/null \
  || fail "SIG Mesh label left must be 2pt after the icon right edge."

rg -n 'make.bottom.equalTo\(iconImageView.snp.bottom\).offset\(SCRYFrom\(-2\)\)' "$header_view" >/dev/null \
  || fail "SIG Mesh label bottom must be 2pt above the icon bottom."

rg -n 'var stateViewHorizontalOffset: CGFloat' "$header_view" >/dev/null \
  || fail "Gateway header state style must expose a horizontal offset for the whole status item."

rg -n 'return SCRXFrom\(-12\)' "$header_view" >/dev/null \
  || fail "SIG Mesh status item must move 12pt left as a whole."

rg -n 'make.centerX.equalToSuperview\(\).multipliedBy\(0.5\).offset\(gatewayStateStyle.stateViewHorizontalOffset\)' "$header_view" >/dev/null \
  || fail "Gateway state item centerX must apply the style-specific horizontal offset."

rg -n "func makeGatewayInformationHeaderView" "$gateway_controller" >/dev/null \
  || fail "GatewayViewController must allow subclasses to configure the header view."

rg -n "override func makeGatewayInformationHeaderView" "$wifi_controller" >/dev/null \
  || fail "WiFiGatewayViewController must configure its own header view."

rg -n "headerView.setGatewayStateStyle\\(\\.sigMesh\\)" "$wifi_controller" >/dev/null \
  || fail "WiFiGatewayViewController must set the left status style to SIG Mesh."

rg -n '"sig_mesh" = "SIG Mesh";' "$en_strings" >/dev/null \
  || fail "English localization must define sig_mesh."

rg -n '"sig_mesh" = "SIG Mesh";' "$zh_strings" >/dev/null \
  || fail "Chinese localization must define sig_mesh and keep the technical name unchanged."

rg -n 'networkTypeLabel = UILabel\(text: "4G"' "$header_view" >/dev/null \
  || fail "Right-side 4G status view must remain unchanged for this task."

echo "PASS: WiFi Gateway SIG Mesh header status configuration matches expected behavior."
