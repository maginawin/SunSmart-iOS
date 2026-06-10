# Select Group(s) Name Width Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 kinetic switch、battery power switch、ac power switch Edit 页面进入 `Select Group(s)` 后，iPad 上 group name 被固定 200pt 宽度截断的问题。

**Architecture:** 保持现有 controller 和数据流不变，只调整共享 `SwitchSelectGroupsViewCell` 的 Auto Layout 约束。`nameLabel` 从固定最大宽度改为根据右侧 on/off 按钮动态限制，三类 Edit 入口因复用同一 cell 自动获得一致布局。

**Tech Stack:** Swift、UIKit、SnapKit、SunSmart 现有 `SCRXFrom`/`SCRYFrom` 尺寸工具、Xcode iPhoneOS build。

---

## 文件结构

- Modify: `SunSmart/Main/Device/Switches/View/SwitchSelectGroupsViewCell.swift`
  - 负责 `Select Group(s)` 列表 cell 布局。
  - 本次只调整 `nameLabel` 和 `onoffBtn` 的水平约束/压缩优先级。
- Reference: `SunSmart/Main/Device/Switches/Controller/SwitchSelectGroupsViewController.swift`
  - Kinetic edit 页和部分 Group 维度只读入口使用该 controller。
  - 不修改。
- Reference: `SunSmart/Main/Device/Device1.5/Common/GroupSelection/Controller/PJDeviceGroupSelectionViewController.swift`
  - Battery/AC edit 页使用该 controller。
  - 不修改。

## Task 1: 调整 Select Group(s) cell 名称宽度

**Files:**
- Modify: `SunSmart/Main/Device/Switches/View/SwitchSelectGroupsViewCell.swift:42-56`

- [ ] **Step 1: 记录当前约束根因**

Run:

```bash
nl -ba SunSmart/Main/Device/Switches/View/SwitchSelectGroupsViewCell.swift | sed -n '33,58p'
```

Expected: 输出中仍可看到 `make.width.lessThanOrEqualTo(SCRXFrom(200))`，说明当前 name label 使用固定最大宽度。

- [ ] **Step 2: 修改 name label 与 on/off 按钮约束**

在 `setupUI()` 内将 `nameLabel` 约束改为：

```swift
nameLabel.snp.makeConstraints { make in
    make.left.equalTo(selectImageView.snp.right).offset(SCRXFrom(8))
    make.right.lessThanOrEqualTo(onoffBtn.snp.left).offset(SCRXFrom(-8))
    make.centerY.equalToSuperview()
}
```

并在 `onoffBtn` 加入 view 后设置：

```swift
onoffBtn.setContentCompressionResistancePriority(.required, for: .horizontal)
onoffBtn.setContentHuggingPriority(.required, for: .horizontal)
```

实现时需要注意 `nameLabel` 的右侧约束依赖 `onoffBtn`，因此应先创建并加入 `onoffBtn`，再给 `nameLabel` 建立完整约束；或先创建 `onoffBtn` 属性但延后添加约束，避免引用未初始化 view。

- [ ] **Step 3: 静态确认固定 200pt 限制已移除**

Run:

```bash
rg -n "width\\.lessThanOrEqualTo\\(SCRXFrom\\(200\\)\\)|onoffBtn\\.snp\\.left|setContentCompressionResistancePriority|setContentHuggingPriority" SunSmart/Main/Device/Switches/View/SwitchSelectGroupsViewCell.swift
```

Expected:
- 不再匹配 `width.lessThanOrEqualTo(SCRXFrom(200))`。
- 能匹配 `onoffBtn.snp.left`。
- 能匹配 `setContentCompressionResistancePriority`。
- 能匹配 `setContentHuggingPriority`。

- [ ] **Step 4: 静态确认三个入口仍复用同一 cell**

Run:

```bash
rg -n "SwitchSelectGroupsViewCell|SwitchSelectGroupsViewController|PJDeviceGroupSelectionViewController" SunSmart/Main/Device/Switches SunSmart/Main/Device/Device1.5/NEightKeySwitches SunSmart/Main/Device/Device1.5/Common/GroupSelection -g '*.swift'
```

Expected:
- `SwitchSelectGroupsViewController` 注册并 dequeue `SwitchSelectGroupsViewCell`。
- `PJDeviceGroupSelectionViewController` 注册并 dequeue `SwitchSelectGroupsViewCell`。
- `DeviceSwitchViewController` 仍通过 `SwitchSelectGroupsViewController` 进入 Kinetic group selection。
- `PJPreAddEightKeySwitchesVC` 仍通过 `PJDeviceGroupSelectionViewController` 进入 Battery/AC group selection。

- [ ] **Step 5: 运行 iPhoneOS 构建验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds，不出现 Swift 编译错误或 Auto Layout 相关编译问题。

- [ ] **Step 6: 检查 diff 边界**

Run:

```bash
git diff -- SunSmart/Main/Device/Switches/View/SwitchSelectGroupsViewCell.swift
git diff --check
```

Expected:
- 业务逻辑未改变。
- 只看到 `SwitchSelectGroupsViewCell` 的布局约束调整。
- `git diff --check` 无输出。

- [ ] **Step 7: 提交实现**

Run:

```bash
git add SunSmart/Main/Device/Switches/View/SwitchSelectGroupsViewCell.swift
git diff --cached --name-only
git diff --cached --check
git commit -m "fix: expand select groups name width"
```

Expected:
- staged 文件只有 `SunSmart/Main/Device/Switches/View/SwitchSelectGroupsViewCell.swift`。
- cached diff 检查无输出。
- commit 创建成功。

## Self-Review

- Spec 覆盖：Task 1 覆盖 iPad 宽度、8pt 间距、三类 Edit 入口、单行截断、不改业务逻辑和 iPhoneOS build 验证。
- Placeholder scan：本文没有未决占位项。
- Type consistency：使用现有 `SwitchSelectGroupsViewCell`、`nameLabel`、`onoffBtn`、SnapKit 约束 API，名称与当前代码一致。
