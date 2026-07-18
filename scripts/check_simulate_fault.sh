#!/usr/bin/env bash
set -euo pipefail

section_file="SunSmart/Main/Device/View/SimulateFaultSectionView.swift"
controller_file="SunSmart/Main/Device/View/SimulateFaultViewController.swift"
legacy_overlay_file="SunSmart/Main/Device/View/SimulateFaultOverlayView.swift"
request_file="SunSmart/Common/Network/SimulateFaultRequest.swift"
api_file="SunSmart/Common/Network/NetowrkReqeustApi.swift"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

test -f "$section_file" || fail "SimulateFaultSectionView.swift is missing"
grep -Fq 'UICollectionViewDelegateFlowLayout' "$section_file" || fail "section must use collection view flow layout"
grep -Fq 'SimulateFaultGridMetrics.collectionHeight' "$section_file" || fail "section must derive collection height from grid metrics"
grep -Fq 'isHighlighted' "$section_file" || fail "button cell must provide transient highlight feedback"
grep -Fq 'onAction?(configuration.items[indexPath.item].action)' "$section_file" || fail "section must expose the typed action"

test -f "$request_file" || fail "SimulateFaultRequest.swift is missing"
grep -Fq 'case simulateFault(payload: SimulateFaultRequestPayload)' "$api_file" \
  || fail "network API must expose simulateFault"
grep -Fq 'return "/temporary/device/alert/add"' "$api_file" \
  || fail "simulateFault must use the temporary device alert endpoint"
grep -Fq 'case .simulateFault(let payload):' "$api_file" \
  || fail "simulateFault must encode its typed payload"
grep -Fq 'return payload.parameters' "$api_file" \
  || fail "simulateFault must send the complete JSON body"
test "$(grep -c 'SimulateFaultRequest.swift in Sources' SunSmart.xcodeproj/project.pbxproj)" -eq 8 \
  || fail "all four app targets must compile SimulateFaultRequest.swift"

test -f "$controller_file" || fail "SimulateFaultViewController.swift is missing"
test ! -f "$legacy_overlay_file" || fail "legacy SimulateFaultOverlayView.swift must be removed"
grep -Fq 'final class SimulateFaultViewController: UIViewController' "$controller_file" \
  || fail "Simulate Fault must be implemented as a view controller"
grep -Fq 'modalPresentationStyle = .overFullScreen' "$controller_file" \
  || fail "Simulate Fault must use full-screen custom presentation"
grep -Fq 'private let dimmingControl = UIControl()' "$controller_file" \
  || fail "Simulate Fault must use a dedicated background control"
grep -Fq 'UIColor.black.withAlphaComponent(Layout.dimmingAlpha)' "$controller_file" \
  || fail "Simulate Fault must use the Figma dimming background"
grep -Fq 'static let dimmingAlpha: CGFloat = 0.30' "$controller_file" \
  || fail "Simulate Fault dimming alpha must be 30 percent"
grep -Fq 'static let contentCornerRadius: CGFloat = 20' "$controller_file" \
  || fail "Simulate Fault content must use the Figma top corner radius"
grep -Fq 'dimmingControl.addTarget(self, action: #selector(dismissFromBackground), for: .touchUpInside)' "$controller_file" \
  || fail "only the background control must dismiss Simulate Fault on tap"
grep -Fq 'contentView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]' "$controller_file" \
  || fail "only the top content corners must be rounded"
grep -Fq 'private var lastPresentationHeight: CGFloat = 0' "$controller_file" \
  || fail "Simulate Fault must re-evaluate scrolling when container height changes"
grep -Fq 'private func handleAction(_ action: SimulateFaultAction)' "$controller_file" \
  || fail "Simulate Fault actions must be handled inside the new controller"
grep -Fq 'self?.handleAction(action)' "$controller_file" \
  || fail "section actions must terminate inside the new controller"
grep -Fq 'private let node: Node' "$controller_file" \
  || fail "Simulate Fault controller must retain the selected node"
grep -Fq 'private var isSending = false' "$controller_file" \
  || fail "Simulate Fault must prevent duplicate HTTP requests"
grep -Fq 'NetworkRequest.shared.request(.simulateFault(payload: payload))' "$controller_file" \
  || fail "Simulate Fault actions must call the HTTP endpoint"
grep -Fq 'XWHUDManager.showCustomHUD(withMessage: "simulate_fault_sending".localizedString, isWindow: true)' "$controller_file" \
  || fail "Simulate Fault must show a window Sending HUD"
grep -Fq 'XWHUDManager.showSuccessTipHUD("successful".localizedString)' "$controller_file" \
  || fail "Simulate Fault must reuse the success HUD"
grep -Fq 'XWHUDManager.showErrorTipHUD("failed".localizedString)' "$controller_file" \
  || fail "Simulate Fault must reuse the failure HUD"
grep -Fq 'UIScrollView' "$controller_file" \
  || fail "system sheet content must remain scrollable"
grep -Fq 'spacePermissionChangedNotificaitonName' "$controller_file" \
  || fail "the controller must observe effective permission changes"
grep -Fq 'modalPresentationStyle = .automatic' "$controller_file" \
  && fail "system automatic presentation cannot reproduce the Figma position and dimming"
grep -Eq 'sheetPresentationController|\.detents[[:space:]]*=' "$controller_file" \
  && fail "custom full-screen presentation must not depend on system sheet sizing"
grep -Eq 'UITapGestureRecognizer|UIPanGestureRecognizer|UIGestureRecognizerDelegate' "$controller_file" \
  && fail "content gestures must not dismiss Simulate Fault"
grep -Eq 'MeshAPI|sendMessage' "$controller_file" \
  && fail "Simulate Fault must not send device commands"
grep -Fq 'black_debug' "$controller_file" || fail "sheet header must use black_debug"
grep -A3 -F 'headerImageView.snp.makeConstraints' "$controller_file" \
  | grep -Fq 'make.width.height.equalTo(30)' \
  || fail "black_debug header image must render at 30 by 30 points"
grep -Fq 'menu_debug' "$controller_file" && fail "sheet header must not use the menu icon"

en_strings="SunSmart/en.lproj/Localizable.strings"
zh_strings="SunSmart/zh-Hans.lproj/Localizable.strings"

check_string() {
  local file="$1"
  local line="$2"
  grep -Fq "$line" "$file" || fail "$file is missing: $line"
}

check_string "$en_strings" '"simulate_fault" = "Simulate Fault";'
check_string "$en_strings" '"simulate_fault_motion_sensor" = "Motion Sensor";'
check_string "$en_strings" '"simulate_fault_photocell_sensor" = "Photocell Sensor";'
check_string "$en_strings" '"simulate_fault_light_status" = "Light Status";'
check_string "$en_strings" '"simulate_fault_minor_3" = "Minor (3)";'
check_string "$en_strings" '"simulate_fault_major_2" = "Major (2)";'
check_string "$en_strings" '"simulate_fault_critical_1" = "Critical (1)";'
check_string "$en_strings" '"simulate_fault_normal" = "Normal";'
check_string "$en_strings" '"simulate_fault_fault" = "Fault";'
check_string "$en_strings" '"simulate_fault_dim" = "Dim";'
check_string "$en_strings" '"simulate_fault_flicker" = "Flicker";'
check_string "$en_strings" '"simulate_fault_dim_flicker" = "Dim Flicker";'
check_string "$en_strings" '"simulate_fault_off" = "Off";'
check_string "$en_strings" '"simulate_fault_sending" = "Sending...";'

check_string "$zh_strings" '"simulate_fault" = "模拟故障";'
check_string "$zh_strings" '"simulate_fault_motion_sensor" = "移动传感器";'
check_string "$zh_strings" '"simulate_fault_photocell_sensor" = "光感传感器";'
check_string "$zh_strings" '"simulate_fault_light_status" = "灯具状态";'
check_string "$zh_strings" '"simulate_fault_minor_3" = "轻微 (3)";'
check_string "$zh_strings" '"simulate_fault_major_2" = "严重 (2)";'
check_string "$zh_strings" '"simulate_fault_critical_1" = "紧急 (1)";'
check_string "$zh_strings" '"simulate_fault_normal" = "正常";'
check_string "$zh_strings" '"simulate_fault_fault" = "故障";'
check_string "$zh_strings" '"simulate_fault_dim" = "调光";'
check_string "$zh_strings" '"simulate_fault_flicker" = "闪烁";'
check_string "$zh_strings" '"simulate_fault_dim_flicker" = "调光闪烁";'
check_string "$zh_strings" '"simulate_fault_off" = "关闭";'
check_string "$zh_strings" '"simulate_fault_sending" = "发送中...";'

test -f "SunSmart/Assets.xcassets/Common/menu_debug.imageset/menu_debug@3x.png" || fail "menu_debug assets are incomplete"
test -f "SunSmart/Assets.xcassets/Common/black_debug.imageset/black_debug@3x.png" || fail "black_debug assets are incomplete"
jq -e '.images | map(.filename) == ["menu_debug.png", "menu_debug@2x.png", "menu_debug@3x.png"]' \
  "SunSmart/Assets.xcassets/Common/menu_debug.imageset/Contents.json" >/dev/null || fail "menu_debug Contents.json is invalid"
jq -e '.images | map(.filename) == ["black_debug.png", "black_debug@2x.png", "black_debug@3x.png"]' \
  "SunSmart/Assets.xcassets/Common/black_debug.imageset/Contents.json" >/dev/null || fail "black_debug Contents.json is invalid"

light_file="SunSmart/Main/Device/Controller/DeviceLightViewController.swift"

grep -Fq 'let menuWidth = SCRXFrom(140)' "$light_file" \
  || fail "Light menu must be wide enough for Simulate Fault"
grep -Fq 'icon: UIImage(named: "menu_debug")' "$light_file" \
  || fail "Light menu must use menu_debug"
grep -Fq 'title: "simulate_fault".localizedString' "$light_file" \
  || fail "Light menu must use the localized Simulate Fault title"
grep -Fq 'guard space.deviceOperates.contains(.edit)' "$light_file" \
  || fail "presentation must re-check effective edit capability"
grep -Fq 'let controller = SimulateFaultViewController(space: space)' "$light_file" \
  && fail "Light controller must pass the selected node"
grep -Fq 'let controller = SimulateFaultViewController(space: space, node: node)' "$light_file" \
  || fail "Light controller must pass the selected node"
grep -Fq 'present(controller, animated: true)' "$light_file" \
  || fail "Light controller must use standard modal presentation"
grep -Eq 'simulateFaultOverlayView|simulateFaultInteractivePop|restoreSimulateFaultInteractivePopGesture|handleSimulateFaultAction' "$light_file" \
  && fail "Light controller must not retain legacy overlay lifecycle code"
grep -Fq 'SimulateFaultViewController.swift' SunSmart.xcodeproj/project.pbxproj \
  || fail "all app targets must reference SimulateFaultViewController.swift"
grep -Fq 'SimulateFaultOverlayView.swift' SunSmart.xcodeproj/project.pbxproj \
  && fail "project must not reference the legacy overlay file"

simulate_line=$(grep -n 'title: "simulate_fault".localizedString' "$light_file" | tail -1 | cut -d: -f1)
refresh_line=$(grep -n 'title: "refresh".localizedString' "$light_file" | tail -1 | cut -d: -f1)
test "$simulate_line" -gt "$refresh_line" || fail "Simulate Fault must be appended after Refresh"

matches=$(grep -R -l 'title: "simulate_fault".localizedString' SunSmart/Main/Device --include='*.swift')
test "$matches" = "$light_file" || fail "Simulate Fault menu must exist only in DeviceLightViewController"

printf 'PASS: Simulate Fault contract is present.\n'
