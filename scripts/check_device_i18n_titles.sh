#!/usr/bin/env bash
set -u

device_info_file="SunSmart/Main/Device/Controller/DeviceInformationViewController.swift"
light_file="SunSmart/Main/Device/Controller/DeviceLightViewController.swift"
en_strings="SunSmart/en.lproj/Localizable.strings"
zh_strings="SunSmart/zh-Hans.lproj/Localizable.strings"

failures=0

fail() {
  printf 'FAIL: %s\n' "$1"
  failures=$((failures + 1))
}

expect_contains() {
  local file="$1"
  local pattern="$2"
  local description="$3"

  if ! grep -Fq "$pattern" "$file"; then
    fail "$description"
  fi
}

expect_not_contains() {
  local file="$1"
  local pattern="$2"
  local description="$3"

  if grep -Fq "$pattern" "$file"; then
    fail "$description"
  fi
}

expect_not_contains "$device_info_file" 'title: "Version Identifier"' "Device information still hardcodes Version Identifier."
expect_contains "$device_info_file" 'title: "version_identifier".localizedString' "Device information does not localize Version Identifier."

expect_not_contains "$light_file" 'title: "Set Proxy"' "Light menu still hardcodes Set Proxy."
expect_contains "$light_file" 'title: "set_proxy".localizedString' "Light menu does not localize Set Proxy."

expect_not_contains "$light_file" 'title: "Reboot"' "Light menu still hardcodes Reboot."
expect_contains "$light_file" 'title: "reboot".localizedString' "Light menu does not localize Reboot."

expect_not_contains "$light_file" 'UILabel(text: "Relay"' "Light detail still hardcodes Relay."
expect_contains "$light_file" 'UILabel(text: "relay".localizedString' "Light detail does not localize Relay."

for strings_file in "$en_strings" "$zh_strings"; do
  expect_contains "$strings_file" '"PID"' "$strings_file is missing PID key."
  expect_contains "$strings_file" '"address"' "$strings_file is missing address key."
  expect_contains "$strings_file" '"version_identifier"' "$strings_file is missing version_identifier key."
  expect_contains "$strings_file" '"set_proxy"' "$strings_file is missing set_proxy key."
  expect_contains "$strings_file" '"reboot"' "$strings_file is missing reboot key."
  expect_contains "$strings_file" '"relay"' "$strings_file is missing relay key."
done

expect_contains "$zh_strings" '"PID" = "产品ID";' "Chinese PID translation should be 产品ID."
expect_contains "$zh_strings" '"address" = "地址";' "Chinese address translation should be 地址."
expect_contains "$zh_strings" '"version_identifier" = "版本标识符";' "Chinese version_identifier translation should be 版本标识符."
expect_contains "$zh_strings" '"set_proxy" = "设置代理";' "Chinese set_proxy translation should be 设置代理."
expect_contains "$zh_strings" '"reboot" = "重启";' "Chinese reboot translation should be 重启."
expect_contains "$zh_strings" '"relay" = "中继";' "Chinese relay translation should be 中继."

if [ "$failures" -gt 0 ]; then
  exit 1
fi

printf 'PASS: targeted device i18n titles are localized.\n'
