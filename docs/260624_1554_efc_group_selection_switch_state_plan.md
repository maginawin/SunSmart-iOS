# EFC Group Selection Switch State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task in this workspace. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 EFC Edit > Group > Select Group(s) 页面中右侧 Group 开关与左侧选择状态互相污染的问题。

**Architecture:** 在共享 Group Selection context 中加入右侧开关策略，默认保持现有入口行为，EFC 入口显式使用“Group 非空即可控制”的策略。共享 cell 负责完整重置右侧按钮状态，控制器只根据策略传入是否可控与当前 on/off 状态。

**Tech Stack:** iOS UIKit, Swift, SnapKit, NordicSigMeshSDK, shell contract script, xcodebuild.

---

## 文件结构

- Modify: `SunSmart/Main/Device/Device1.5/Common/GroupSelection/Model/PJDeviceGroupSelectionContext.swift`
  - 定义 Group Selection 右侧开关策略，默认兼容现有行为。
- Modify: `SunSmart/Main/Device/Device1.5/Common/GroupSelection/Controller/PJDeviceGroupSelectionViewController.swift`
  - 根据 context 策略渲染右侧按钮，并保证行点击、Select all 不修改右侧开关状态。
- Modify: `SunSmart/Main/Device/Switches/View/SwitchSelectGroupsViewCell.swift`
  - 增加统一配置右侧按钮的方法，完整重置 `isEnabled`、`isSelected`、图片和 callback。
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift`
  - EFC Edit 入口显式传入“非空 Group 可控制”策略。
- Modify: `scripts/check_efc_controller_flows.sh`
  - 增加 contract，锁定 EFC 入口使用新策略，并禁止 EFC 选择页右侧开关依赖在线状态。

注意：当前工作区已有 restore brightness 相关未提交改动，实施本计划时不要回退、格式化或混入这些改动。

---

### Task 1: 扩展 Group Selection Context

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/Common/GroupSelection/Model/PJDeviceGroupSelectionContext.swift`

- [ ] **Step 1: 打开 context 文件确认当前结构**

Run:

```bash
sed -n '1,120p' SunSmart/Main/Device/Device1.5/Common/GroupSelection/Model/PJDeviceGroupSelectionContext.swift
```

Expected: 能看到 `PJDeviceGroupSelectionContext` 只有 `title`、`groups`、`selectedGroupAddresses`、`disabledGroupAddresses`、`disabledSelectionTip`。

- [ ] **Step 2: 增加右侧开关策略类型**

在 `PJDeviceGroupSelectionContext.swift` 中加入：

```swift
enum PJDeviceGroupSelectionSwitchControlPolicy {
    case onlineNodesOnly
    case nonEmptyGroup

    func canControl(_ group: Group) -> Bool {
        switch self {
        case .onlineNodesOnly:
            return group.nodes.contains(where: { $0.state })
        case .nonEmptyGroup:
            return !group.nodes.isEmpty
        }
    }
}
```

并在 `PJDeviceGroupSelectionContext` 中增加字段：

```swift
let switchControlPolicy: PJDeviceGroupSelectionSwitchControlPolicy
```

- [ ] **Step 3: 增加兼容初始化器**

给 `PJDeviceGroupSelectionContext` 添加显式 init，默认策略保持现状：

```swift
init(
    title: String,
    groups: [Group],
    selectedGroupAddresses: [UInt16],
    disabledGroupAddresses: Set<UInt16>,
    disabledSelectionTip: String,
    switchControlPolicy: PJDeviceGroupSelectionSwitchControlPolicy = .onlineNodesOnly
) {
    self.title = title
    self.groups = groups
    self.selectedGroupAddresses = selectedGroupAddresses
    self.disabledGroupAddresses = disabledGroupAddresses
    self.disabledSelectionTip = disabledSelectionTip
    self.switchControlPolicy = switchControlPolicy
}
```

- [ ] **Step 4: 编译前静态检查调用点**

Run:

```bash
rg -n "PJDeviceGroupSelectionContext|switchControlPolicy|PJDeviceGroupSelectionViewController\\(" SunSmart/Main/Device/Device1.5 -g '*.swift'
```

Expected: 现有 `.init(...)` 调用仍能通过默认参数表达原行为；EFC 入口将在 Task 4 单独改成 `.nonEmptyGroup`。

---

### Task 2: 统一配置 SwitchSelectGroupsViewCell 右侧按钮

**Files:**
- Modify: `SunSmart/Main/Device/Switches/View/SwitchSelectGroupsViewCell.swift`

- [ ] **Step 1: 增加右侧按钮配置方法**

在 `SwitchSelectGroupsViewCell` 中新增：

```swift
func configureOnOffButton(isEnabled: Bool, isOn: Bool, action: ((Bool) -> Void)?) {
    onoffBtn.isEnabled = isEnabled
    onoffBtn.isSelected = isEnabled && isOn
    onoffBtn.setImage(UIImage(named: "scene_group_off"), for: .normal)
    onoffBtn.setImage(UIImage(named: "scene_group_on"), for: .selected)
    onoffBtn.setImage(UIImage(named: "scene_group_disable"), for: .disabled)
    onOffCallback = action
}
```

- [ ] **Step 2: 保持按钮 action 只通过 callback 通知**

确认 `onoffBtnAction` 保持如下语义，不直接改 `sender.isSelected`：

```swift
@objc private func onoffBtnAction(sender: UIButton) {
    onOffCallback?(!sender.isSelected)
}
```

Expected: cell 不自行修改状态，状态只由控制器回写，避免空组和复用污染。

- [ ] **Step 3: 搜索旧调用点，准备逐步迁移**

Run:

```bash
rg -n "cell\\.onoffBtn|onOffCallback" SunSmart/Main/Device/Device1.5/Common SunSmart/Main/Device/Device1.5/FireAlarm SunSmart/Main/Device/Device1.5/NEightKeySwitches SunSmart/Main/Device/Switches -g '*.swift'
```

Expected: 本计划只迁移共享 `PJDeviceGroupSelectionViewController`，不改旧 `SwitchSelectGroupsViewController` 和旧 EFC 专用页面，避免扩大影响面。

---

### Task 3: 在共享 Group Selection 中按策略渲染右侧开关

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/Common/GroupSelection/Controller/PJDeviceGroupSelectionViewController.swift`

- [ ] **Step 1: 替换 cellForRowAt 中右侧按钮渲染逻辑**

将当前 `if group.nodes.isEmpty || !group.nodes.contains(where: { $0.state }) { ... } else { ... }` 和后续 `cell.onOffCallback = ...` 替换成：

```swift
let canControlGroup = context.switchControlPolicy.canControl(group)
cell.configureOnOffButton(isEnabled: canControlGroup, isOn: group.isOn) { [weak cell] isOn in
    guard canControlGroup else { return }
    cell?.onoffBtn.isSelected = isOn
    group.isOn = isOn
    MeshAPI.setGroupOnOffState(address: group.address.address, isOn: isOn)
}
```

- [ ] **Step 2: 确认行点击只改选择状态**

确认 `didSelectRowAt` 只保留以下行为：

```swift
if let index = selectedGroupAddresses.firstIndex(of: address) {
    selectedGroupAddresses.remove(at: index)
} else {
    selectedGroupAddresses.append(address)
}

selectedGroupAddresses.sort()
updateSelectAllState()
tableView.reloadRows(at: [indexPath], with: .none)
```

Expected: 不读取、不修改 `group.isOn`，不调用 `MeshAPI.setGroupOnOffState`。

- [ ] **Step 3: 确认 Select all 只改选择状态**

确认 `selectAllAction` 只改 `selectedGroupAddresses` 并 reload：

```swift
if sender.isSelected {
    let addresses = selectableGroups.map(\.address.address)
    selectedGroupAddresses = Array(Set(selectedGroupAddresses).union(addresses)).sorted()
} else {
    selectedGroupAddresses.removeAll { address in
        selectableGroups.contains(where: { $0.address.address == address })
    }
}

tableView.reloadData()
```

Expected: 不读取、不修改 `group.isOn`，不调用 `MeshAPI.setGroupOnOffState`。

---

### Task 4: EFC Edit 入口启用非空 Group 可控制策略

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift`

- [ ] **Step 1: 修改 EFC Group Selection context**

在 `.associatedGroups` 分支创建 `PJDeviceGroupSelectionViewController` 的 context 时加入：

```swift
switchControlPolicy: .nonEmptyGroup
```

完整 context 应包含：

```swift
context: .init(
    title: "select_group(s)".localizedString,
    groups: DeviceEmerFireStore.shared.selectableGroups(),
    selectedGroupAddresses: state.selectedGroupAddresses(),
    disabledGroupAddresses: state.disabledAssociatedGroupAddresses(),
    disabledSelectionTip: "Not selectable. This group is already associated with a device of the same type.".localizedString,
    switchControlPolicy: .nonEmptyGroup
)
```

- [ ] **Step 2: 确认 8-key 入口不传策略**

Run:

```bash
sed -n '245,270p' SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
```

Expected: 8-key 入口仍不传 `switchControlPolicy`，继续默认 `.onlineNodesOnly`。

---

### Task 5: 增加 EFC Contract

**Files:**
- Modify: `scripts/check_efc_controller_flows.sh`

- [ ] **Step 1: 增加 EFC 入口策略断言**

在 EFC Edit 相关断言附近追加：

```bash
assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift" \
  "switchControlPolicy: .nonEmptyGroup" \
  "EFC Select Group(s) must allow controlling any non-empty group, independent of online state."
```

- [ ] **Step 2: 增加共享默认策略断言**

追加：

```bash
assert_contains "SunSmart/Main/Device/Device1.5/Common/GroupSelection/Model/PJDeviceGroupSelectionContext.swift" \
  "switchControlPolicy: PJDeviceGroupSelectionSwitchControlPolicy = .onlineNodesOnly" \
  "Shared group selection must keep existing default switch control behavior for non-EFC callers."
```

- [ ] **Step 3: 增加非空 Group 策略断言**

追加：

```bash
assert_contains "SunSmart/Main/Device/Device1.5/Common/GroupSelection/Model/PJDeviceGroupSelectionContext.swift" \
  "return !group.nodes.isEmpty" \
  "EFC non-empty group policy must not depend on node online state."
```

- [ ] **Step 4: 增加统一 cell 配置断言**

追加：

```bash
assert_contains "SunSmart/Main/Device/Switches/View/SwitchSelectGroupsViewCell.swift" \
  "func configureOnOffButton(isEnabled: Bool, isOn: Bool, action: ((Bool) -> Void)?)" \
  "Group selection cells must reset right-side switch state through a single configuration method."
```

---

### Task 6: 验证与提交

**Files:**
- Verify: modified Swift files
- Verify: `scripts/check_efc_controller_flows.sh`

- [ ] **Step 1: 检查 diff 范围**

Run:

```bash
git diff -- SunSmart/Main/Device/Device1.5/Common/GroupSelection/Model/PJDeviceGroupSelectionContext.swift SunSmart/Main/Device/Device1.5/Common/GroupSelection/Controller/PJDeviceGroupSelectionViewController.swift SunSmart/Main/Device/Switches/View/SwitchSelectGroupsViewCell.swift SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift scripts/check_efc_controller_flows.sh
```

Expected: diff 只包含本计划相关改动；不要回退当前工作区已有 restore brightness 改动。

- [ ] **Step 2: 运行 contract**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected: 输出不包含 `FAIL:`，命令退出码为 0。

- [ ] **Step 3: 运行 whitespace 检查**

Run:

```bash
git diff --check
```

Expected: 无输出，退出码为 0。

- [ ] **Step 4: 运行 iPhoneOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 5: 提交实现改动**

只暂存本计划涉及文件。当前工作区已有其他未提交改动时，先用 `git status --short` 和 `git diff --cached` 确认 staged 范围。

Run:

```bash
git add SunSmart/Main/Device/Device1.5/Common/GroupSelection/Model/PJDeviceGroupSelectionContext.swift SunSmart/Main/Device/Device1.5/Common/GroupSelection/Controller/PJDeviceGroupSelectionViewController.swift SunSmart/Main/Device/Switches/View/SwitchSelectGroupsViewCell.swift SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift scripts/check_efc_controller_flows.sh
git diff --cached --check
git commit -m "fix: stabilize EFC group selection switches"
```

Expected: commit succeeds and does not include unrelated files.
