# Battery Power Switch Dim Click Transaction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 Battery Power Switch 页面中间开关面板 dim up/down 连续单击只生效一次的问题。

**Architecture:** 保持现有 `PJEightKeySwitchVirtualGroupControlSender` 作为 App 页面模拟发送入口，只在 dim up/down 单击消息创建时把 `GenericDeltaSetUnacknowledged.continueTransaction` 设为 `false`。同按钮 `200ms` 过滤、真实 Battery Power Switch profile 配置、haptic 和长按弹窗行为全部保持不变。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、SIG Mesh Generic Level Delta、Xcode workspace `SunSmart.xcworkspace`。

---

## File Structure

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
  - 更新 `PJEightKeySwitchVirtualGroupControlSender.keyTapMessage(index:switchData:)` 中 dim up/down 消息创建逻辑。
  - 新增一个私有 helper，集中创建独立事务的 `GenericDeltaSetUnacknowledged`。
  - 保持 `keyTapThrottleInterval`、`shouldAcceptKeyTap`、haptic 和长按逻辑不变。

本计划不修改 `PJEightKeySwitchData.batteryPowerSwitchKeyConfigurations(appKeyIndex:)`，避免影响真实设备 profile 配置。

---

### Task 1: 修复 dim up/down 单击事务语义

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`

- [ ] **Step 1: 记录当前相关代码位置**

Run:

```bash
rg -n "keyTapThrottleInterval|shouldAcceptKeyTap|GenericDeltaSetUnacknowledged|dimmingStepLevel|keyTapMessage" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
```

Expected:

- 能看到 `keyTapThrottleInterval: TimeInterval = 0.2`。
- 能看到 `shouldAcceptKeyTap(index:now:)` 使用 `lastKeyTapTimes[index]` 做同按钮过滤。
- 能看到 dim up/down 当前直接返回 `GenericDeltaSetUnacknowledged(delta: Self.dimmingStepLevel)` 和负值。

- [ ] **Step 2: 修改 dim up/down 消息创建路径**

在 `PJEightKeySwitchVirtualGroupControlSender` 中新增 helper：

```swift
private func dimmingDeltaMessage(delta: Int32) -> GenericDeltaSetUnacknowledged {
    var message = GenericDeltaSetUnacknowledged(delta: delta)
    message.continueTransaction = false
    return message
}
```

将 `keyTapMessage(index:switchData:)` 中的 dim up/down 分支改为：

```swift
case 4:
    return dimmingDeltaMessage(delta: Self.dimmingStepLevel)
case 5:
    return dimmingDeltaMessage(delta: -Self.dimmingStepLevel)
```

完整目标片段应为：

```swift
private func keyTapMessage(index: Int, switchData: PJEightKeySwitchData) -> MeshMessage? {
    switch index {
    case 0...3:
        return topKeyMessage(index: index, switchData: switchData)
    case 4:
        return dimmingDeltaMessage(delta: Self.dimmingStepLevel)
    case 5:
        return dimmingDeltaMessage(delta: -Self.dimmingStepLevel)
    case 6:
        return GenericOnOffSetUnacknowledged(true)
    case 7:
        return GenericOnOffSetUnacknowledged(false)
    default:
        return nil
    }
}

private func dimmingDeltaMessage(delta: Int32) -> GenericDeltaSetUnacknowledged {
    var message = GenericDeltaSetUnacknowledged(delta: delta)
    message.continueTransaction = false
    return message
}
```

- [ ] **Step 3: 确认未改动过滤和 haptic**

Run:

```bash
rg -n "keyTapThrottleInterval: TimeInterval = 0.2|lastKeyTapTimes\\[index\\]|triggerTapFeedback|impactOccurred|minimumPressDuration|longPressAction" SunSmart/Main/Device/Device1.5/NEightKeySwitches
```

Expected:

- `PJEightKeySwitchMonitorVC.swift` 中仍有 `keyTapThrottleInterval: TimeInterval = 0.2`。
- `shouldAcceptKeyTap(index:now:)` 仍按 `lastKeyTapTimes[index]` 过滤。
- `PJEightKeySwitchMonitorKeyView.swift` 中 haptic 相关调用仍存在，未移动触发时机。

- [ ] **Step 4: 静态确认 dim 消息使用新事务**

Run:

```bash
rg -n "dimmingDeltaMessage|continueTransaction = false|GenericDeltaSetUnacknowledged\\(delta:" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
```

Expected:

- 只有 `dimmingDeltaMessage(delta:)` 内直接创建 `GenericDeltaSetUnacknowledged(delta:)`。
- `dimmingDeltaMessage(delta:)` 内设置 `message.continueTransaction = false`。
- `keyTapMessage(index:switchData:)` 的 dim up/down 分支调用 `dimmingDeltaMessage`。

- [ ] **Step 5: 编译验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- 命令退出码为 `0`。
- 输出包含 `** BUILD SUCCEEDED **`。

- [ ] **Step 6: 手工验证**

在真实或测试 Mesh 网络中验证：

- 打开 Battery Power Switch 设备页。
- 对 dim up 按钮连续单击，间隔大于 `200ms`，每次应继续约 `+20%`。
- 对 dim down 按钮连续单击，间隔大于 `200ms`，每次应继续约 `-20%`。
- 在 `200ms` 内快速重复点击同一个按钮，只应响应第一次。
- Scene、brightness、ON、OFF、长按亮度弹窗、长按 ON 弹出 AUTO 的行为保持不变。

- [ ] **Step 7: 提交实现**

只提交本任务修改的实现文件，不要纳入已有无关改动。

Run:

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
git commit -m "fix: send dim clicks as new transactions"
```

Expected:

- commit 只包含 `PJEightKeySwitchMonitorVC.swift`。
- 不包含 `docs/`、本地化、数据库、电池展示或其他既有未提交改动。

---

## Self-Review

- Spec coverage：计划覆盖保留 `200ms` 过滤、dim up/down 独立事务、不改 profile、不改 haptic、不新增重发机制。
- Scope check：本计划只修改一个发送 helper，属于单一可独立验证任务。
- Type consistency：`GenericDeltaSetUnacknowledged.continueTransaction` 是 SDK 消息的可写属性；`PJEightKeySwitchVirtualGroupControlSender.keyTapMessage(index:switchData:)` 当前返回 `MeshMessage?`，返回具体 `GenericDeltaSetUnacknowledged` 类型兼容。

