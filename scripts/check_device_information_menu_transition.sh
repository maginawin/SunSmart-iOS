#!/usr/bin/env bash
set -u

failures=0

assert_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"

  if ! grep -Fq "$pattern" "$file"; then
    printf 'FAIL: %s\n' "$message" >&2
    printf '  expected: %s\n' "$pattern" >&2
    printf '  in file: %s\n' "$file" >&2
    failures=$((failures + 1))
  fi
}

menu_file="SunSmart/Common/View/MenuPopView.swift"
navigation_file="SunSmart/Common/Extension/UIViewController+Extension.swift"
information_pattern='title: "information".localizedString, hideAnimation: false, performsActionAfterDismiss: true'
push_helper_pattern='pushDeviceInformationController'

assert_contains "$menu_file" \
  'func dismiss(animation: Bool = true, completion: (() -> Void)? = nil)' \
  "MenuPopView.dismiss must expose a completion so navigation actions can run after the menu is removed."

assert_contains "$menu_file" \
  'var performsActionAfterDismiss: Bool = false' \
  "MenuPopView.MenuItem must keep default action timing but allow navigation items to opt in."

assert_contains "$menu_file" \
  'if item.performsActionAfterDismiss {' \
  "MenuPopView.didSelectRowAt must branch on the opt-in action timing."

assert_contains "$menu_file" \
  'dismiss(animation: item.hideAnimation) {' \
  "Opt-in menu items must dismiss before executing their action."

assert_contains "$menu_file" \
  'DispatchQueue.main.async {' \
  "Opt-in menu item actions must run on the next main-queue turn after the menu has been removed."

assert_contains "$navigation_file" \
  'func pushDeviceInformationController(_ viewController: UIViewController)' \
  "Device Information pages must use a dedicated push helper."

assert_contains "$navigation_file" \
  'navigationController.view.layer.addMoveInAnimation(duration: 0.3, type: .push, animationOrientation: .fromRight)' \
  "Device Information push helper must add an explicit right-to-left push transition."

assert_contains "$navigation_file" \
  'navigationController.pushViewController(viewController, animated: false)' \
  "Device Information push helper must rely on the explicit layer transition, not UIKit default push timing."

assert_contains "SunSmart/Main/Device/Controller/DeviceLightViewController.swift" \
  "$information_pattern" \
  "Light device Information must dismiss menu before push."

assert_contains "SunSmart/Main/Device/Controller/DeviceLightViewController.swift" \
  "$push_helper_pattern" \
  "Light device Information must use the explicit device Information push helper."

assert_contains "SunSmart/Main/Device/Controller/DeviceBaseViewController.swift" \
  "$information_pattern" \
  "Base device Information must dismiss menu before push for future subclasses."

assert_contains "SunSmart/Main/Device/Controller/DeviceBaseViewController.swift" \
  "$push_helper_pattern" \
  "Base device Information must use the explicit device Information push helper."

assert_contains "SunSmart/Main/Device/Dali/Controller/DaliMasterViewController.swift" \
  "$information_pattern" \
  "DALI device Information must dismiss menu before push."

assert_contains "SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift" \
  "$information_pattern" \
  "Shared Gateway Information must dismiss menu before push."

assert_contains "SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift" \
  "$push_helper_pattern" \
  "Shared Gateway Information must use the explicit device Information push helper."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift" \
  "$information_pattern" \
  "Emergency Fire Controller Information must dismiss menu before push."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift" \
  "$push_helper_pattern" \
  "Emergency Fire Controller Information must use the explicit device Information push helper."

assert_contains "SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift" \
  "$information_pattern" \
  "Battery/AC Power Switch Information must dismiss menu before push."

assert_contains "SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift" \
  "$push_helper_pattern" \
  "Battery/AC Power Switch Information must use the explicit device Information push helper."

if [ "$failures" -gt 0 ]; then
  exit 1
fi

printf 'PASS: device Information menu items dismiss before pushing.\n'
