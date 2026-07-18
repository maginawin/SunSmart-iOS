# WiFi/4G Gateway Child Page Modal Dismissal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 禁止 WiFi/4G Gateway 的 `WiFi DFU` 与 `Information` 页面下滑关闭整个模态导航栈，并在返回 Gateway 主页面后恢复原状态。

**Architecture:** 只在 `WiFiGatewayViewController` 维护一次受保护子页面流程的原始 `isModalInPresentation` 状态。两个菜单入口先启用外层导航控制器保护，再保持现有 push 行为；Gateway 主页面重新 `viewDidAppear` 后恢复原值，从而覆盖后续子页面并避开取消交互式返回时的过早恢复。

**Tech Stack:** Swift、UIKit、现有 `NavigationViewController`、Bash/rg 静态 contract、Xcode iPhoneOS build。

## Global Constraints

- 所有文档与回复使用简体中文，用户可见 UI 文案保持英文并支持 English、简体中文国际化。
- 改动仅限 WiFi/4G Gateway 的 `WiFi DFU` 与 `Information` 入口，不改变其他设备、其他菜单入口或共享控制器行为。
- 返回 Gateway 主页面后恢复进入受保护流程前的 `isModalInPresentation` 原值。
- 不新增用户可见文案、Auth 信息、依赖、资源或 target 配置。
- 不重构或格式化无关代码。
- 验证必须使用 iPhoneOS generic destination，不使用 Simulator 或 shell 包装 `xcodebuild`。
- 当前会话按用户偏好使用 Inline Execution，不使用 subagents。

---

### Task 1: 用聚焦 contract 驱动模态导航栈保护

**Files:**
- Create: `scripts/check_wifi_gateway_child_page_modal_dismissal.sh`
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`

**Interfaces:**
- Consumes: `WiFiGatewayViewController.navigationController`、`UIViewController.isModalInPresentation`、现有 `moreClick()` 两个菜单回调。
- Produces: `modalDismissalStateBeforeProtectedFlow: Bool?`、`preventModalStackDismissalUntilReturn()`、`restoreModalStackDismissalIfNeeded()`；两个目标入口调用统一保护方法。

- [ ] **Step 1: 写入失败的聚焦 contract**

创建 `scripts/check_wifi_gateway_child_page_modal_dismissal.sh`：

```bash
#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

gateway="SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift"

[ -f "$gateway" ] || fail "missing WiFi Gateway controller"
rg -n 'private var modalDismissalStateBeforeProtectedFlow: Bool\?' "$gateway" >/dev/null || fail "missing saved modal dismissal state"
rg -n 'private func preventModalStackDismissalUntilReturn\(\)' "$gateway" >/dev/null || fail "missing modal dismissal protection helper"
rg -n 'modalDismissalStateBeforeProtectedFlow = navigationController\.isModalInPresentation' "$gateway" >/dev/null || fail "protection helper must preserve the previous state"
rg -n 'navigationController\.isModalInPresentation = true' "$gateway" >/dev/null || fail "protection helper must disable interactive modal dismissal"
rg -n 'private func restoreModalStackDismissalIfNeeded\(\)' "$gateway" >/dev/null || fail "missing modal dismissal restoration helper"
rg -n 'navigationController\?\.isModalInPresentation = previousState' "$gateway" >/dev/null || fail "restoration helper must restore the previous state"
rg -n 'override func viewDidAppear\(_ animated: Bool\)' "$gateway" >/dev/null || fail "Gateway page must restore only after it fully reappears"
rg -n 'restoreModalStackDismissalIfNeeded\(\)' "$gateway" >/dev/null || fail "Gateway page does not restore modal dismissal"

protection_call_count=$(grep -Fc 'preventModalStackDismissalUntilReturn()' "$gateway")
[ "$protection_call_count" -eq 3 ] || fail "protection helper must be declared once and called by exactly two menu entries"

echo "PASS: WiFi/4G Gateway child page modal dismissal checks"
```

- [ ] **Step 2: 运行 contract 并确认 RED**

Run: `bash scripts/check_wifi_gateway_child_page_modal_dismissal.sh`

Expected: exit code `1`，输出 `FAIL: missing saved modal dismissal state`。

- [ ] **Step 3: 在 Gateway 控制器实现最小状态保护**

在 `WiFiGatewayViewController` 的私有状态区增加：

```swift
private var modalDismissalStateBeforeProtectedFlow: Bool?
```

在现有 `viewWillAppear` / `viewWillDisappear` 生命周期附近增加：

```swift
override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    restoreModalStackDismissalIfNeeded()
}
```

在 `moreClick()` 附近增加：

```swift
private func preventModalStackDismissalUntilReturn() {
    guard let navigationController else { return }
    if modalDismissalStateBeforeProtectedFlow == nil {
        modalDismissalStateBeforeProtectedFlow = navigationController.isModalInPresentation
    }
    navigationController.isModalInPresentation = true
}

private func restoreModalStackDismissalIfNeeded() {
    guard let previousState = modalDismissalStateBeforeProtectedFlow else { return }
    navigationController?.isModalInPresentation = previousState
    modalDismissalStateBeforeProtectedFlow = nil
}
```

在 `WiFi DFU` 与 `Information` 两个菜单回调内，创建目标控制器后、执行 push 前分别加入：

```swift
self.preventModalStackDismissalUntilReturn()
```

保留 `WiFi DFU` 的系统 push 与 `Information` 的现有自定义 push 动画，不改其他菜单项。

- [ ] **Step 4: 运行 contract 并确认 GREEN**

Run: `bash scripts/check_wifi_gateway_child_page_modal_dismissal.sh`

Expected: exit code `0`，输出 `PASS: WiFi/4G Gateway child page modal dismissal checks`。

- [ ] **Step 5: 检查聚焦差异并提交**

Run: `git diff --check`

Expected: exit code `0`，无输出。

Run: `git diff -- scripts/check_wifi_gateway_child_page_modal_dismissal.sh SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`

Expected: 仅包含聚焦 contract、状态保存/恢复、两个入口调用。

```bash
git add scripts/check_wifi_gateway_child_page_modal_dismissal.sh SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift
git commit -m "fix: protect gateway child pages from modal dismissal"
```

### Task 2: 全量验证与实施总结

**Files:**
- Create: `docs/260720_1756_wifi_gateway_child_page_modal_dismissal_implementation_summary.md`
- Verify: `SunSmart.xcworkspace`
- Verify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
- Verify: `scripts/check_wifi_gateway_child_page_modal_dismissal.sh`

**Interfaces:**
- Consumes: Task 1 完成的 modal dismissal contract 与实现。
- Produces: 四品牌 target 编译证据和聚焦实施总结。

- [ ] **Step 1: 重新运行聚焦 contract 与差异检查**

Run: `bash scripts/check_wifi_gateway_child_page_modal_dismissal.sh`

Expected: exit code `0`，输出 `PASS: WiFi/4G Gateway child page modal dismissal checks`。

Run: `git diff --check HEAD~1..HEAD`

Expected: exit code `0`，无输出。

- [ ] **Step 2: 构建 SunSmart iPhoneOS target**

Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: exit code `0`，日志末尾包含 `BUILD SUCCEEDED`。

- [ ] **Step 3: 构建 Archipelago iPhoneOS target**

Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: exit code `0`，日志末尾包含 `BUILD SUCCEEDED`。

- [ ] **Step 4: 构建 SLG Sync Plus iPhoneOS target**

Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: exit code `0`，日志末尾包含 `BUILD SUCCEEDED`。

- [ ] **Step 5: 构建 SylSmart iPhoneOS target**

Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: exit code `0`，日志末尾包含 `BUILD SUCCEEDED`。

- [ ] **Step 6: 写入实施总结**

创建 `docs/260720_1756_wifi_gateway_child_page_modal_dismissal_implementation_summary.md`，明确记录：

```markdown
# WiFi/4G Gateway 子页面下滑关闭保护实施总结

## 改动

- 两个指定菜单入口 push 前保护外层模态导航栈。
- 保护状态覆盖目标页面继续进入的子页面。
- Gateway 主页面完整返回后恢复进入前的下滑关闭状态。
- 共享 Information 页面及其他入口保持不变。

## 验证

- 聚焦 contract：通过。
- `git diff --check`：通过。
- SunSmart iPhoneOS Debug build：通过。
- Archipelago iPhoneOS Debug build：通过。
- SLG Sync Plus iPhoneOS Debug build：通过。
- SylSmart iPhoneOS Debug build：通过。

## 手工验收边界

编译与静态 contract 不能替代真机手势验证；需要在 WiFi Gateway 与 4G Gateway 上分别确认两个入口无法下滑关闭，并确认返回 Gateway 主页面后恢复下滑关闭。
```

- [ ] **Step 7: 提交实施总结**

Run: `git diff --check`

Expected: exit code `0`，无输出。

```bash
git add docs/260720_1756_wifi_gateway_child_page_modal_dismissal_implementation_summary.md
git commit -m "docs: summarize gateway modal dismissal protection"
```
