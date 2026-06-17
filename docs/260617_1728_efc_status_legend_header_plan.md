# EFC Status Legend Header Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 对齐 EFC 设备页 status legend 的 Figma 设计，并停止在该页面主动展示 Disabled 功能。

**Architecture:** 只修改 legend header 的私有布局和监控页状态到 status rows 的映射。保留历史 disabled enum 分支作为兼容，不删除协议或数据模型能力，避免影响旧状态解析和异常兜底。

**Tech Stack:** UIKit, SnapKit, Swift, Xcode iPhoneOS build.

---

## Files

- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireAlarmStatusLegendHeaderView.swift`
  - 负责 Figma legend header 的尺寸、字体、图标和可见项。
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRendering.swift`
  - 负责页面状态到四个 status row icon 的映射。

## Task 1: 对齐 Legend Header UI

- [x] **Step 1: 调整布局常量**

在 `EmerFireAlarmStatusLegendHeaderView.Layout` 中更新：

```swift
static let height = SCRYFrom(32)
static let horizontalInset = SCRXFrom(41)
static let itemSpacing = SCRXFrom(24)
static let indicatorSize = SCRXFrom(20)
static let indicatorImageInset = SCRXFrom(2)
static let cornerRadius = SCRYFrom(2)
static let containerCornerRadius = SCRYFrom(10)
```

- [x] **Step 2: 调整文字样式**

把 `titleLabel` 的颜色和字号改为：

```swift
let label = UILabel(text: nil, textColor: RGB(64, 79, 102), fontSize: 12, fontWeight: .light)
```

- [x] **Step 3: 调整图标实际视觉尺寸**

把 `indicatorImageView` 约束从等于 `indicatorView` 全边改为 inset：

```swift
indicatorImageView.snp.makeConstraints { make in
    make.edges.equalTo(indicatorView).inset(Layout.indicatorImageInset)
}
```

- [x] **Step 4: 调整 icon 和 label 间距**

把 `titleLabel` 左侧约束改为：

```swift
make.left.equalTo(indicatorView.snp.right).offset(SCRXFrom(4))
```

- [x] **Step 5: 移除 Disabled legend item**

删除 `disabledItem` 属性，并将 stack arranged subviews 改为：

```swift
let stackView = UIStackView(arrangedSubviews: [triggeredItem, resumeItem, inactiveItem])
```

- [x] **Step 6: 按内容等距分布**

把 stack distribution 改为：

```swift
stackView.distribution = .equalSpacing
```

- [x] **Step 7: 调整容器背景**

把 `containerView.backgroundColor` 改为：

```swift
view.backgroundColor = RGB(250, 250, 250)
```

## Task 2: 停止主动展示 Disabled 状态图标

- [x] **Step 1: 修改不可操作状态行映射**

在 `EmerFireAlarmMonitorRendering.updateStatusSetRows(for:)` 中删除局部 `disabled` 常量，并把不可操作状态分支改为不赋值：

```swift
case .loading, .repair, .offline, .disabled:
    break
```

这样四个 row 会保持初始 `.inactive`。

- [x] **Step 2: 保留兼容状态**

不删除 `EmerFireAlarmMonitorDisplayState.disabled`、`EmerFireAlarmStatusSetView.RowStatus.disabled` 和 `EmergencyFireControllerIconName.Monitor.StatusSet.disabled`，避免历史状态或旧设备回包进入该分支时破坏调用链。

## Task 3: 验证

- [x] **Step 1: 静态搜索**

Run:

```bash
rg -n "disabledItem|Disabled" SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireAlarmStatusLegendHeaderView.swift
```

Expected: no output.

- [x] **Step 2: 检查差异**

Run:

```bash
git diff --check
```

Expected: no output.

- [x] **Step 3: iPhoneOS 构建**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.
