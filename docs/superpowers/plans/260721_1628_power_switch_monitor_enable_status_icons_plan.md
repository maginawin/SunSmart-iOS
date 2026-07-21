# Battery/AC Power Switch Monitor Enable Status Icons Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task with Inline Execution. Steps use checkbox (`- [ ]`) syntax for tracking. Do not use subagents for this plan.

**Goal:** 将 Battery/AC power switch Monitor 底部 Settings 弹窗中的顶部只读 UISwitch 和两个 mini switch 图例替换为指定的 20 × 20 状态图片，同时保持图片完全不可点击并保留既有 Enable/Disable 发送流程。

**Architecture:** 改动集中在 `PJEightKeySwitchMonitorStatusSetView`：顶部用一个动态 `UIImageView` 映射 `State.isEnabled`，展开图例用两个固定 `UIImageView` 表达 Enable/Disable，并删除只服务于旧 switch 外观的私有 UI 实现。`PJEightKeySwitchMonitorVC` 的 `enableChanged` 绑定和 Virtual/Battery/AC 更新发送路径保持不变，未来恢复交互时可重新接入控件。

**Tech Stack:** Swift, UIKit, SnapKit, Xcode workspace `SunSmart.xcworkspace`

## Global Constraints

- 只调整 Battery/AC power switch Monitor 页面底部 Settings 弹窗。
- 顶部 Enable 状态为 true 时使用 `sensor_occupy`，false 时使用 `sensor_unoccupy`。
- 展开图例的 Enable 左侧固定使用 `sensor_occupy`，Disable 左侧固定使用 `sensor_unoccupy`。
- 三张图片的布局尺寸均为 20 × 20，使用 `scaleAspectFit`。
- 三张图片均不触发状态切换或设备命令；顶部图片必须消费自身区域触摸，不能穿透到 `headerButton` 导致弹窗展开或收起。
- 保留 `enableChanged`、Controller 绑定以及 Virtual/Battery/AC Enable/Disable 更新发送流程。
- 不修改独立 Edit Switch、Group Power Switch、Group Link、Groups 列表或其他 Monitor 交互。
- 不新增用户可见文案、Auth 信息、本地化、资源、target、依赖、协议、存储或 SDK 改动。
- 当前工作区已有用户的离线设备图标资源和 English/简体中文本地化改动；不得修改、取消暂存或提交这些文件。
- 构建验证必须直接使用 iPhoneOS `xcodebuild`，不得使用 Simulator 或 shell 包装。

---

## File Structure

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift`
  - 用图片替换顶部 UISwitch 和展开图例 mini switch。
  - 配置顶部动态图片、图例固定图片、20 × 20 约束和顶部触摸消费。
  - 移除旧 UISwitch、透明 shield、mini switch builder 和私有绘制类。
  - 保留 `enableChanged` 回调接口。
- Inspect only: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
  - 确认 `bottomView.enableChanged`、Virtual 更新、Battery activation/Tx Enable 和 AC 直接发送流程保持存在。
- Verify only: `SunSmart/Assets.xcassets/Group/sensor_occupy.imageset`
- Verify only: `SunSmart/Assets.xcassets/Group/sensor_unoccupy.imageset`
- No changes: `SunSmart/en.lproj/Localizable.strings`、`SunSmart/zh-Hans.lproj/Localizable.strings`、现有离线设备图标资源、project/target 配置、依赖和 `NordicSigMeshSDK`。

---

### Task 1: 用不可点击状态图片替换弹窗中的三处 Switch 外观

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift:20-363`
- Inspect: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift:247-249`
- Inspect: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift:394-470`

**Interfaces:**
- Consumes: `PJEightKeySwitchMonitorStatusSetView.State.isEnabled: Bool`、现有 Assets `sensor_occupy` / `sensor_unoccupy`。
- Produces: `enableStatusImageView: UIImageView` 的动态顶部状态；`enableLegendIconView` / `disabledLegendIconView` 的固定图例；保留 `enableChanged: ((Bool) -> Void)?` 外部接口。

- [ ] **Step 1: 记录并保护当前工作区中的用户改动**

Run:

```bash
git status --short
```

Expected: 能看到用户已有的离线设备图标资源和 `SunSmart/en.lproj/Localizable.strings`、`SunSmart/zh-Hans.lproj/Localizable.strings` 修改。记录其 staged/unstaged 状态；后续不得对这些路径执行 restore、reset、add 或普通无路径限定的 commit。

- [ ] **Step 2: 运行改动前的 UI 基线检查**

Run:

```bash
rg -n "enableSwitch = UISwitch|enableSwitchTouchShield|enableLegendSwitch|disabledLegendSwitch|PJEightKeySwitchMiniSwitchLegendView|func enableValueChanged" SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift
```

Expected: 六类旧 UISwitch / mini switch 逻辑均有匹配。

Run:

```bash
rg -n "enableStatusImageView|enableLegendIconView|disabledLegendIconView|sensor_occupy|sensor_unoccupy" SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift
```

Expected: 命令退出码为 1 且没有匹配，证明目标图片展示尚未实现。

- [ ] **Step 3: 替换属性和 configure 状态映射**

删除 `Layout` 中只供 mini switch 使用的常量：

```swift
static let miniSwitchSize = CGSize(width: SCRXFrom(30), height: SCRYFrom(20))
```

删除 `Palette` 中只供 mini switch 绘制使用的颜色：

```swift
static let switchDisabledTrack = RGB(238, 238, 238)
static let switchDisabledKnob = UIColor.white
```

将顶部属性：

```swift
let enableSwitch = UISwitch()
private let enableSwitchTouchShield = UIControl()
```

替换为：

```swift
private let enableStatusImageView = UIImageView()
```

将图例属性：

```swift
private let enableLegendSwitch = PJEightKeySwitchMiniSwitchLegendView()
private let disabledLegendSwitch = PJEightKeySwitchMiniSwitchLegendView()
```

替换为：

```swift
private let enableLegendIconView = UIImageView(image: UIImage(named: "sensor_occupy"))
private let disabledLegendIconView = UIImageView(image: UIImage(named: "sensor_unoccupy"))
```

保留以下回调接口不变：

```swift
var enableChanged: ((Bool) -> Void)?
```

将 `configure(state:)` 中旧 switch 配置：

```swift
enableSwitch.setOn(state.isEnabled, animated: false)
enableSwitch.isEnabled = true
enableSwitchTouchShield.isHidden = false
```

替换为：

```swift
enableStatusImageView.image = UIImage(named: state.isEnabled ? "sensor_occupy" : "sensor_unoccupy")
```

并删除：

```swift
enableLegendSwitch.isOn = true
disabledLegendSwitch.isOn = false
```

Expected: 顶部图片只由 `State.isEnabled` 决定；两个图例图片在属性初始化时固定使用正确资源；`State.isPending` 保持在 State 接口中但不改变只读图片映射。

- [ ] **Step 4: 替换顶部布局并保证触摸不穿透**

删除整个 `enableValueChanged(_:)` 私有 action：

```swift
@objc private func enableValueChanged(_ sender: UISwitch) {
    enableSwitch.setOn(sender.isOn, animated: true)
    enableChanged?(sender.isOn)
}
```

将 `setupUI()` 中从 `enableSwitch.addTarget` 到 `enableSwitchTouchShield` 约束结束的旧代码替换为：

```swift
enableStatusImageView.contentMode = .scaleAspectFit
enableStatusImageView.isUserInteractionEnabled = true
contentView.addSubview(enableStatusImageView)
enableStatusImageView.snp.makeConstraints { make in
    make.centerY.equalTo(headerButton)
    make.right.equalToSuperview().offset(-SCRXFrom(24))
    make.width.height.equalTo(SCRXFrom(20))
}
```

将 `enableTitleLabel` 的右侧约束：

```swift
make.right.equalTo(enableSwitch.snp.left).offset(-SCRXFrom(8))
```

替换为：

```swift
make.right.equalTo(enableStatusImageView.snp.left).offset(-SCRXFrom(8))
```

Expected:

- 顶部图片布局为 20 × 20、`scaleAspectFit`、右侧 24pt 语义间距。
- `isUserInteractionEnabled = true` 使图片自身成为 hit-test 目标；由于没有 gesture、target 或 action，点击图片区域不会触发业务，也不会穿透到下层 `headerButton`。
- `Enable` 文案仍在图片左侧 8pt。

- [ ] **Step 5: 替换展开图例并删除 mini switch 私有实现**

删除 `setupUI()` 中：

```swift
enableLegendSwitch.isOn = true
disabledLegendSwitch.isOn = false
```

将 legend stack 中：

```swift
makeSwitchLegendItem(switchView: enableLegendSwitch, label: enableLegendLabel),
makeSwitchLegendItem(switchView: disabledLegendSwitch, label: disabledLegendLabel)
```

替换为：

```swift
makeLegendItem(iconView: enableLegendIconView, label: enableLegendLabel),
makeLegendItem(iconView: disabledLegendIconView, label: disabledLegendLabel)
```

保留 `makeLegendItem(iconView:label:)` 的现有实现：

```swift
private func makeLegendItem(iconView: UIImageView, label: UILabel) -> UIStackView {
    iconView.contentMode = .scaleAspectFit
    iconView.snp.makeConstraints { make in
        make.width.height.equalTo(SCRXFrom(20))
    }
    let stackView = UIStackView(arrangedSubviews: [iconView, label])
    stackView.axis = .horizontal
    stackView.alignment = .center
    stackView.spacing = SCRXFrom(4)
    return stackView
}
```

删除整个 `makeSwitchLegendItem(switchView:label:)` 方法，并删除文件末尾整个 `PJEightKeySwitchMiniSwitchLegendView` 私有类。

Expected: Group Linked、Group Unlinked、Enable、Disable 四个图例项统一使用 20 × 20 图片和 4pt 图文间距；status card 和弹窗高度约束不改变。

- [ ] **Step 6: 运行图片、清理和发送流程保留检查**

Run:

```bash
rg -n "enableStatusImageView|enableLegendIconView|disabledLegendIconView|sensor_occupy|sensor_unoccupy|width\.height\.equalTo\(SCRXFrom\(20\)\)|isUserInteractionEnabled = true" SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift
```

Expected: 顶部动态图片、两个固定图例资源、20 × 20 图片约束和顶部触摸消费均有匹配。

Run:

```bash
rg -n "enableSwitch = UISwitch|enableSwitchTouchShield|enableLegendSwitch|disabledLegendSwitch|PJEightKeySwitchMiniSwitchLegendView|func enableValueChanged|makeSwitchLegendItem|miniSwitchSize|switchDisabledTrack|switchDisabledKnob" SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift
```

Expected: 命令退出码为 1 且没有匹配。

Run:

```bash
rg -n "var enableChanged|bottomView\.enableChanged|startTxEnableUpdate|updateUnlinkedVirtualEnable|PJEightKeySwitchTxEnableFlow|sendACTxEnable|MeshBatteryPowerSwitchTxEnableSender" SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
```

Expected: `enableChanged` API、Controller 绑定、Virtual 更新、Battery flow 和 AC 发送路径全部保留。

- [ ] **Step 7: 检查范围、格式与用户改动保护**

Run:

```bash
git diff -- SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift
```

Expected: 只包含三处图片替换、顶部 hit testing 和旧 switch UI 的局部清理。

Run:

```bash
git diff --check -- SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift
```

Expected: 没有输出。

Run:

```bash
git diff -- SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj Podfile
```

Expected: Controller、project 和 Podfile 不出现本需求产生的差异；本地化若有输出，只能是 Step 1 已记录的用户既有改动，内容和 staged/unstaged 状态不得因本任务变化。

再次运行：

```bash
git status --short
```

Expected: 除目标 View 外，用户既有离线图标资源和本地化改动保持 Step 1 的状态。

- [ ] **Step 8: 执行 iPhoneOS 构建验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 输出 `** BUILD SUCCEEDED **`。

- [ ] **Step 9: 完成运行时验收记录**

在可用测试数据或真机环境中核对：

1. Battery Enable/Disable 顶部分别显示 `sensor_occupy` / `sensor_unoccupy`。
2. AC Enable/Disable 顶部分别显示 `sensor_occupy` / `sensor_unoccupy`。
3. 展开图例的 Enable/Disable 左侧分别显示 `sensor_occupy` / `sensor_unoccupy`。
4. 三张图片视觉尺寸均为 20 × 20。
5. 点击顶部状态图片不改变状态、不发送命令，也不展开或收起弹窗。
6. 点击两个图例图片不产生任何效果。
7. Group Link、Groups 列表和弹窗其他区域的展开/收起行为保持现状。

Expected: 有对应环境的用例全部符合；如果当前缺少真机或状态数据，实施总结必须明确列出未执行项，不能以编译成功替代运行时行为验证。

- [ ] **Step 10: 使用路径限定提交业务实现**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift
git commit --only SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift -m "fix: use icons for power switch enable status"
```

Expected: 提交只包含目标 View 文件；用户已暂存的离线图标资源继续留在 index 中，用户的本地化修改保持原状态，不进入本次提交。

---

## Plan Self-Review

- Spec coverage: Steps 3–5 覆盖顶部动态图片、两个固定图例、20 × 20、触摸不穿透和旧 UI 清理；Step 6 覆盖发送路径保留；Step 9 覆盖 Battery/AC 与交互验收。
- Completeness: 每个代码修改都给出精确文件、替换前上下文、目标内容和预期结果。
- Type consistency: `enableStatusImageView`、`enableLegendIconView`、`disabledLegendIconView` 在属性、configure、布局和源码检查中的命名一致；`enableChanged` 保持现有类型。
- Scope: 业务修改仅涉及一个 View 文件；Controller、Assets、本地化、target、依赖和 SDK 均不属于本任务修改范围。
- Workspace safety: 提交使用 `git commit --only`，避免把用户已经 staged 的资源和其他 working-tree 修改卷入提交。
- Verification: 包含改动前基线、改动后映射/清理断言、发送流程保留、范围检查、目标文件 `git diff --check`、iPhoneOS build 和运行时验收记录。
