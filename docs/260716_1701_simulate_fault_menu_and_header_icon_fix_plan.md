# Simulate Fault Menu and Header Icon Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 Light 设备菜单中 `Simulate Fault` 文本被裁切的问题，并将弹窗标题左侧 `black_debug` 的实际显示尺寸调整为 30×30。

**Architecture:** 保持共享 `MenuPopView` 不变，仅扩大 `DeviceLightViewController` 当前菜单实例的宽度。保留 30×30 标题图标容器，只调整内部 `headerImageView` 的尺寸约束；用现有 shell contract 做源码级回归保护。

**Tech Stack:** Swift、UIKit、SnapKit、shell contract、Xcode/iPhoneOS。

## Global Constraints

- 仅修改 Light 设备页的 Simulate Fault 菜单与弹窗标题图标布局。
- 菜单宽度固定为 `SCRXFrom(140)`。
- `black_debug` 图片视图的实际宽高固定为 30×30。
- 不修改共享 `MenuPopView`、字体、行数、权限逻辑、按钮事件或 Mesh 命令行为。
- 验证必须直接使用 `xcodebuild`、iPhoneOS generic destination，不能使用 Simulator 或 shell 包装/日志重定向。
- 不使用 subagents，按 Inline Execution 执行。

---

### Task 1: 增加失败的布局契约

**Files:**
- Modify: `scripts/check_simulate_fault.sh`

**Interfaces:**
- Consumes: `DeviceLightViewController.moreClick()` 中的局部 `menuWidth`；`SimulateFaultViewController.setupUI()` 中的 `headerImageView` SnapKit 约束。
- Produces: 对 `SCRXFrom(140)` 和 `headerImageView` 30×30 约束的源码级回归检查。

- [ ] **Step 1: 写入菜单宽度契约**

在 Light 页面相关检查中加入：

```sh
grep -Fq 'let menuWidth = SCRXFrom(140)' "$light_file" \
  || fail "Light menu must be wide enough for Simulate Fault"
```

- [ ] **Step 2: 写入标题图标尺寸契约**

在 `black_debug` 检查后加入针对 `headerImageView` 约束块的检查：

```sh
grep -A3 -F 'headerImageView.snp.makeConstraints' "$controller_file" \
  | grep -Fq 'make.width.height.equalTo(30)' \
  || fail "black_debug header image must render at 30 by 30 points"
```

- [ ] **Step 3: 运行契约并确认 RED**

Run: `bash scripts/check_simulate_fault.sh`

Expected: FAIL，首先报告 `Light menu must be wide enough for Simulate Fault`。临时单独验证或完成该检查后再次运行时，还应能捕获原有 `headerImageView` 16×16 约束。

### Task 2: 实施最小布局修复

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`
- Modify: `SunSmart/Main/Device/View/SimulateFaultViewController.swift`

**Interfaces:**
- Consumes: Task 1 新增的两个 contract。
- Produces: 宽度为 `SCRXFrom(140)` 的 Light 菜单；实际显示为 30×30 的 `black_debug` 标题图片。

- [ ] **Step 1: 扩大 Light 菜单宽度**

将 `moreClick()` 中：

```swift
let menuWidth = SCRXFrom(114)
```

替换为：

```swift
let menuWidth = SCRXFrom(140)
```

- [ ] **Step 2: 调整标题图片实际尺寸**

保留 `headerIconContainerView` 的 30×30 约束，将 `headerImageView` 约束改为：

```swift
headerImageView.snp.makeConstraints { make in
    make.center.equalToSuperview()
    make.width.height.equalTo(30)
}
```

- [ ] **Step 3: 运行定向契约并确认 GREEN**

Run: `bash scripts/check_simulate_fault.sh`

Expected: `PASS: Simulate Fault contract is present.`

- [ ] **Step 4: 运行相关回归检查**

Run: `bash scripts/check_device_menu_icons.sh`

Expected: PASS，且 Light proxy 图标期望保持 `menu_set_proxy`。

Run: `swiftc SunSmart/Main/Device/Model/SimulateFaultAction.swift Tests/Device/SimulateFaultModelTests.swift -o /tmp/SimulateFaultModelTests`

Expected: 编译成功。

Run: `/tmp/SimulateFaultModelTests`

Expected: `SimulateFaultModelTests passed`。

### Task 3: 完整构建与交付记录

**Files:**
- Create: `docs/260716_1701_simulate_fault_menu_and_header_icon_fix_summary.md`

**Interfaces:**
- Consumes: Task 2 的最终代码与验证输出。
- Produces: 四 target 编译证据和聚焦的实施总结。

- [ ] **Step 1: 检查补丁格式**

Run: `git diff --check`

Expected: 无输出，exit code 0。

- [ ] **Step 2: 直接构建四个品牌 target**

依次运行：

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 四次均输出 `** BUILD SUCCEEDED **`。

- [ ] **Step 3: 写实施总结**

总结必须记录：根因、两处最小代码修改、RED/GREEN 结果、定向脚本结果、模型测试结果、四 target 构建结果，以及仍需真机目视确认菜单文字和 30×30 图标视觉效果。

- [ ] **Step 4: 检查最终工作区边界**

Run: `git status --short`

Expected: 只将本次 Simulate Fault 文件纳入交付说明；保留并明确排除既有的 `AGENTS.md`、Site/Space key 分析文档和 Energy Data 协议分析文档。
