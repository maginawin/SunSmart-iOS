# Battery/AC Power Switch Enable State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 只把 Battery/AC Power Switch Monitor 页面底部弹窗中 `Settings` 同一行的 `Enable` 更新为本地化文案 `Enable State`。

**Architecture:** 为目标 Label 新增 NEightKeySwitches 专用国际化 Key，并只替换 `PJEightKeySwitchMonitorStatusSetView.enableTitleLabel` 的文本来源。通用 `enable` Key、展开图例、Edit 页以及所有布局和业务逻辑保持不变。

**Tech Stack:** Swift、UIKit、SnapKit、iOS `Localizable.strings`、Xcode workspace。

## Global Constraints

- 仅目标 Label 显示 `Enable State`，其他 `Enable` 文案不变。
- English 文案固定为 `Enable State`。
- 简体中文文案固定为 `启用状态`。
- 不修改布局、图标、交互、状态计算、数据流或协议行为。
- 不新增 Auth 信息，不重构或格式化无关文件。
- iOS 构建使用 iPhoneOS generic destination，不使用 Simulator、shell 包装或日志重定向。

---

### Task 1: 新增专用本地化文案并只接入目标 Label

**Files:**

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift:52`
- Modify: `SunSmart/en.lproj/Localizable.strings:1877-1878`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings:1893-1894`
- Test: static localization and scope checks; no dedicated test target exists for this presentation-only copy change

**Interfaces:**

- Consumes: `String.localizedString` and the existing private `enableTitleLabel`.
- Produces: localization Key `neightkeyswitches_enable_state`, whose English value is `Enable State` and simplified-Chinese value is `启用状态`.

- [ ] **Step 1: 记录变更前的失败基线**

Run:

```bash
rg -n '"neightkeyswitches_enable_state"' SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift
```

Expected: exit code `1` and no matches, proving the dedicated Key does not yet exist.

Run:

```bash
rg -n 'enableTitleLabel = UILabel\(text: "enable"\.localizedString' SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift
```

Expected: exactly one match for the current target Label.

- [ ] **Step 2: 新增 English 与简体中文专用 Key**

In `SunSmart/en.lproj/Localizable.strings`, add immediately after `neightkeyswitches_settings`:

```text
"neightkeyswitches_enable_state" = "Enable State";
```

In `SunSmart/zh-Hans.lproj/Localizable.strings`, add in the same NEightKeySwitches section:

```text
"neightkeyswitches_enable_state" = "启用状态";
```

- [ ] **Step 3: 只替换底部折叠栏目标 Label 的 Key**

In `PJEightKeySwitchMonitorStatusSetView.swift`, replace only the `enableTitleLabel` declaration with:

```swift
private let enableTitleLabel = UILabel(text: "neightkeyswitches_enable_state".localizedString, textColor: Title_Color, fontSize: 13, fontWeight: .light, fit: false)
```

Do not modify `enableLegendLabel` in the same file or `PJEightKeySwitchEditorView.enableRowView`.

- [ ] **Step 4: 验证本地化文件语法**

Run:

```bash
plutil -lint SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: both files report `OK`.

- [ ] **Step 5: 验证新 Key 的定义与消费范围**

Run:

```bash
rg -n '"neightkeyswitches_enable_state"' SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift
```

Expected: exactly three matches—one Swift consumer and two localization definitions.

Run:

```bash
rg -n '"enable"\.localizedString' SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchEditorView.swift
```

Expected: exactly two unchanged matches—`enableLegendLabel` and Edit 页 `enableRowView`；目标 `enableTitleLabel` 不再匹配。

- [ ] **Step 6: 检查四个品牌 target 的共享资源归属**

Run:

```bash
rg -n 'Localizable\.strings in Resources' SunSmart.xcodeproj/project.pbxproj
```

Expected: `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 Resources build phase 继续引用同一个 `Localizable.strings` variant group，且 project 文件无修改。

- [ ] **Step 7: 审查差异范围与格式**

Run:

```bash
git diff -- SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: 只有目标 Label 的 Key 替换，以及两份本地化文件各新增一行。

Run:

```bash
git diff --check
```

Expected: exit code `0` with no output.

- [ ] **Step 8: 构建 SunSmart target**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 9: 构建其他共享资源 target**

Run each command separately:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: every command ends with `** BUILD SUCCEEDED **`.

- [ ] **Step 10: 提交聚焦改动**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git commit -m "fix: update power switch enable state label"
```

Expected: one commit containing exactly the three target files.
