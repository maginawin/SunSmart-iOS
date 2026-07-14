# WiFi Firmware Current Version Failed Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 WiFi Firmware Update 页面在 Current version 为 `Failed` 时隐藏已成功获取的云端 latest 固件的问题，同时保持 `UPGRADE` 禁用。

**Architecture:** 保留 `FirmwareVersionViewController` 的共享布局和云端数据渲染，将“是否展示云端固件详情”与“是否启用主按钮”拆成两个默认兼容的 hook。`WiFiFirmwareUpdateViewController` 只在 Current version failed 时放宽详情展示，升级资格继续走现有严格版本比较；BLE/Mesh 页面继续使用默认行为。

**Tech Stack:** Swift、UIKit、SnapKit、现有 shell contract tests、Xcode workspace、iPhoneOS `xcodebuild`

## Global Constraints

- 所有回复、Markdown 文档、计划文档默认使用简体中文；UI 文案保持英文且本次不新增文案。
- 保持改动聚焦，不重构无关模块，不格式化大量无关文件。
- 不修改 NordicSigMeshSDK、`43 14` 协议、latest firmware API、请求模型、Beta Testing `1314` 入口或真实 WiFi DFU 行为。
- 不修改 `43 10` start WiFi DFU 或 `43 11` status 的 App 功能。
- Current version 为 `Failed` 时展示云端固件详情、显示 Refresh、禁用 `UPGRADE`。
- Current version 有效时，仅 New version 严格高于 Current version 才启用 `UPGRADE`。
- Current version 为 `Loading...` 时的详情展示策略保持现状。
- BLE/Mesh 固件页面行为必须保持不变。
- 不修改本地化文件、资源、Xcode target 配置或依赖。
- 验证必须直接运行 `xcodebuild`，使用 iPhoneOS generic destination，不使用 shell 包装、日志重定向或 Simulator。
- 当前 worktree 已位于 `wifi-gateway` 分支；按项目规则使用 Inline Execution，不使用 subagents。

---

## 文件结构

- Modify: `scripts/check_wifi_gateway_firmware_update.sh` — 为详情展示和升级资格解耦增加先失败后通过的静态契约。
- Modify: `SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift` — 增加两个默认兼容 hook，并在共享渲染中分别消费。
- Modify: `SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift` — Current version failed 时覆盖详情展示规则。
- Create: `docs/260714_1730_wifi_firmware_failed_current_version_implementation_summary.md` — 记录实现边界、验证结果和已知限制。

---

### Task 1: 解耦云端固件详情展示与 UPGRADE enablement

**Files:**

- Modify: `scripts/check_wifi_gateway_firmware_update.sh`
- Modify: `SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift:50-75`
- Modify: `SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift:279-318`
- Modify: `SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift:70-90`

**Interfaces:**

- Consumes: `FirmwareServerData`、`isNewServerFirmwareAvailable(_:)`、`CurrentVersionState`、`requiresAdditionalFirmwareReload`。
- Produces: `shouldShowServerFirmwareDetails(_:) -> Bool` 和 `isFirmwarePrimaryActionEnabled(_:) -> Bool` 两个父页面 hook；WiFi failed 状态的详情展示 override。

- [ ] **Step 1: 在 contract script 中写入失败契约**

在 `scripts/check_wifi_gateway_firmware_update.sh` 中，紧接现有 `isNewServerFirmwareAvailable(_:)` 检查后加入：

```bash
rg -n 'func shouldShowServerFirmwareDetails\(_ serverData: FirmwareServerData\) -> Bool' "$parent" >/dev/null || fail "missing server firmware details visibility hook"
rg -n 'func isFirmwarePrimaryActionEnabled\(_ serverData: FirmwareServerData\) -> Bool' "$parent" >/dev/null || fail "missing firmware primary action enablement hook"
default_availability_count=$(grep -Fc 'return isNewServerFirmwareAvailable(serverData)' "$parent")
[ "$default_availability_count" -eq 2 ] || fail "default details and action hooks must preserve existing availability behavior"
rg -n 'if shouldShowServerFirmwareDetails\(newFirmwareData\)' "$parent" >/dev/null || fail "firmware details ignore visibility hook"
rg -n 'downloadBtn\.isEnabled = isFirmwarePrimaryActionEnabled\(newFirmwareData\)' "$parent" >/dev/null || fail "firmware button ignores enablement hook"
```

在 WiFi controller 的版本比较检查后加入：

```bash
rg -n 'override func shouldShowServerFirmwareDetails\(_ serverData: FirmwareServerData\) -> Bool' "$wifi" >/dev/null || fail "WiFi page missing failed-current-version details override"
rg -n 'if case \.failed = currentVersionState' "$wifi" >/dev/null || fail "WiFi details override does not detect failed current version"
rg -n 'return isNewServerFirmwareAvailable\(serverData\)' "$wifi" >/dev/null || fail "WiFi non-failed details must preserve strict comparison"
if rg -n 'override func isFirmwarePrimaryActionEnabled' "$wifi" >/dev/null; then
  fail "WiFi page must not bypass strict primary action enablement"
fi
```

- [ ] **Step 2: 运行 focused contract，确认先失败**

Run:

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
```

Expected: FAIL，首个错误为：

```text
FAIL: missing server firmware details visibility hook
```

失败原因必须是新契约尚未实现，而不是脚本语法或既有契约失败。

- [ ] **Step 3: 在父页面增加两个默认兼容 hook**

在 `FirmwareVersionViewController.swift` 的 `isNewServerFirmwareAvailable(_:)` 后加入完整实现：

```swift
func shouldShowServerFirmwareDetails(_ serverData: FirmwareServerData) -> Bool {
    return isNewServerFirmwareAvailable(serverData)
}

func isFirmwarePrimaryActionEnabled(_ serverData: FirmwareServerData) -> Bool {
    return isNewServerFirmwareAvailable(serverData)
}
```

这两个默认实现不得引用 WiFi 状态，确保 BLE/Mesh 页面继续使用现有版本比较语义。

- [ ] **Step 4: 让共享 updateUI 分别消费两个 hook**

在 `FirmwareVersionViewController.updateUI()` 的 `type.serverData` 分支中，将：

```swift
if isNewServerFirmwareAvailable(newFirmwareData) {
```

替换为：

```swift
if shouldShowServerFirmwareDetails(newFirmwareData) {
```

在详情可见分支末尾，将：

```swift
downloadBtn.isEnabled = true
```

替换为：

```swift
downloadBtn.isEnabled = isFirmwarePrimaryActionEnabled(newFirmwareData)
```

详情不可见分支继续保留：

```swift
downloadBtn.isEnabled = false
```

`requiresAdditionalFirmwareReload` 的后置失败规则必须原样保留：

```swift
if requiresAdditionalFirmwareReload {
    stateLabel.isHidden = true
    reloadBtn.isHidden = false
    downloadBtn.isEnabled = false
}
```

不要在该后置规则中修改 `versionScrollView.isHidden` 或 Current version 卡片约束。

- [ ] **Step 5: WiFi failed 状态只放宽详情展示**

在 `WiFiFirmwareUpdateViewController.swift` 的 `isNewServerFirmwareAvailable(_:)` 后、`loadAdditionalFirmwareData()` 前加入：

```swift
override func shouldShowServerFirmwareDetails(_ serverData: FirmwareServerData) -> Bool {
    if case .failed = currentVersionState {
        return true
    }
    return isNewServerFirmwareAvailable(serverData)
}
```

不要覆盖 `isFirmwarePrimaryActionEnabled(_:)`。父页面默认实现将继续调用 WiFi 已有的严格版本比较，因此 loading/failed 都不会启用 `UPGRADE`。

- [ ] **Step 6: 运行 focused contract，确认通过**

Run:

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
```

Expected:

```text
PASS: WiFi Gateway firmware update static checks
```

- [ ] **Step 7: 检查本任务 diff 和空白错误**

Run:

```bash
git diff -- scripts/check_wifi_gateway_firmware_update.sh SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift
git diff --check
```

Expected:

- diff 只包含新契约、两个父页面 hook、共享渲染的两处调用和 WiFi failed override；
- `git diff --check` 无输出且退出码为 0。

- [ ] **Step 8: 提交功能修复**

```bash
git add scripts/check_wifi_gateway_firmware_update.sh SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift
git commit -m "fix: show wifi firmware when current version fails"
```

Expected: commit 成功，且不包含文档、SDK、本地化、资源或 target 配置改动。

---

### Task 2: 完成全量回归、四 target 构建与总结

**Files:**

- Create: `docs/260714_1730_wifi_firmware_failed_current_version_implementation_summary.md`

**Interfaces:**

- Consumes: Task 1 的详情展示 hook、按钮 enablement hook、WiFi failed override 和现有 WiFi Gateway contract suite。
- Produces: 可审计的回归证据、四 target iPhoneOS build 结果和实现总结。

- [ ] **Step 1: 运行全部 WiFi Gateway 静态回归脚本**

逐条直接运行：

```bash
bash scripts/check_wifi_gateway_apn_removed.sh
bash scripts/check_wifi_gateway_disconnect_clear_credentials.sh
bash scripts/check_wifi_gateway_firmware_update.sh
bash scripts/check_wifi_gateway_info_rows_hidden.sh
bash scripts/check_wifi_gateway_menu_icons.sh
bash scripts/check_wifi_gateway_network_connectivity.sh
bash scripts/check_wifi_gateway_repair_recovery.sh
bash scripts/check_wifi_gateway_server_information_recovery.sh
bash scripts/check_wifi_gateway_sig_mesh_status_header.sh
bash scripts/check_wifi_gateway_wifi_status_header.sh
```

Expected: 10 条命令均退出码为 0，并分别输出对应 `PASS:` 信息。任何失败都先按 `superpowers:systematic-debugging` 定位，不跳过失败继续宣称完成。

- [ ] **Step 2: 构建 SunSmart target**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 退出码 0，输出包含 `** BUILD SUCCEEDED **`。

- [ ] **Step 3: 构建 Archipelago target**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 退出码 0，输出包含 `** BUILD SUCCEEDED **`。

- [ ] **Step 4: 构建 SLG Sync Plus target**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 退出码 0，输出包含 `** BUILD SUCCEEDED **`。

- [ ] **Step 5: 构建 SylSmart target**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 退出码 0，输出包含 `** BUILD SUCCEEDED **`。

- [ ] **Step 6: 写实现总结**

仅在前述 10 个脚本和四个构建全部成功后，创建 `docs/260714_1730_wifi_firmware_failed_current_version_implementation_summary.md` 并写入以下完整内容。如果任一验证失败，先停止总结步骤，使用 `superpowers:systematic-debugging` 定位并修复，重新完成全部验证后再写总结：

```markdown
# WiFi Firmware Current Version Failed Display 实现总结

## 完成内容

- 将云端固件详情展示与主按钮 enablement 拆分为两个默认兼容 hook。
- WiFi Current version 为 `Failed` 时仍展示已获取的 latest 固件详情。
- Failed 状态继续显示 Refresh 并强制禁用 `UPGRADE`。
- Current version 有效时仍仅在 New version 严格更高时启用 `UPGRADE`。
- BLE/Mesh 固件页面继续使用父页面默认行为。

## 改动文件

- `scripts/check_wifi_gateway_firmware_update.sh`
- `SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift`
- `SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift`

## 验证结果

- WiFi Gateway 静态回归脚本：10/10 通过
- SunSmart iPhoneOS build：通过
- Archipelago iPhoneOS build：通过
- SLG Sync Plus iPhoneOS build：通过
- SylSmart iPhoneOS build：通过
- `git diff --check`：通过

## 范围说明

- 未修改 NordicSigMeshSDK、协议、网络接口、本地化、资源或 target 配置。
- 未实现真实 WiFi DFU；`UPGRADE` 继续沿用当前行为。
- Current version 为 `Loading...` 时的固件详情展示策略保持不变。
```

- [ ] **Step 7: 最终验证工作树和 diff**

Run:

```bash
git diff --check
git status --short
```

Expected:

- `git diff --check` 无输出且退出码为 0；
- `git status --short` 只显示新建的 implementation summary，业务代码和脚本已经在 Task 1 commit 中提交。

- [ ] **Step 8: 提交实现总结**

```bash
git add docs/260714_1730_wifi_firmware_failed_current_version_implementation_summary.md
git commit -m "docs: summarize wifi firmware failed version display"
```

Expected: commit 成功。

- [ ] **Step 9: 完成前证据核对**

Run:

```bash
git status --short
git log -3 --oneline
```

Expected:

- `git status --short` 无输出；
- 最近提交包含功能修复 commit 和实现总结 commit；
- 最终答复只报告本轮实际执行并看到成功输出的检查，不把未执行或失败项描述为通过。
