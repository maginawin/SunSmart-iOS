# 特殊 CCT 产品默认值 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `0x0A78/0x2013` 与 `0x0A78/0x24B1` 统一为特殊 CCT 产品，使 Device Parameter Settings 默认 `Single White`、默认 CCT 范围 `2700K...5000K`，并隐藏 PWM frequency。

**Architecture:** 默认值规则继续集中在本地 `NordicSigMeshSDK` 的 `Node` 属性扩展，App 侧通过现有 `default*` 和 `effective*` 属性自然复用。PWM frequency 属于 App 业务能力判断，继续在 `MeshNetwork+SunSmart.swift` 的 `supportPwmFrequency` 中维护排除规则。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK Swift Package、Xcode workspace `SunSmart.xcworkspace`。

---

## 文件结构

| 文件 | 责任 |
| --- | --- |
| `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift` | SDK 层特殊 CCT 产品判断；派生 `defaultChangeControlPage`、`defaultAbsoluteCctRange`、`effective*` 行为 |
| `SunSmart/Common/Data/MeshNetwork+SunSmart.swift` | App 层 PWM frequency 支持判断；决定参数页、读取、设置、列表、筛选是否出现 PWM |

不新增文件，不调整数据库、云同步字段、本地化文案或 UI 结构。

## Task 1: 更新 SDK 特殊 CCT 产品判断

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift`

- [ ] **Step 1: 写入变更前静态检查，确认 `0x24B1` 尚未被特殊默认值规则覆盖**

Run:

```bash
rg -n "isSingleWhiteDefaultCctProduct|0x24B1|0x2013" /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift
```

Expected: 只看到 `isSingleWhiteDefaultCctProduct` 中的 `0x2013`，看不到 `0x24B1`。这说明当前检查会失败于新需求。

- [ ] **Step 2: 修改特殊产品判断**

在 `Node+Propertys.swift` 中将当前实现：

```swift
var isSingleWhiteDefaultCctProduct: Bool {
    companyIdentifier == 0x0A78 && productIdentifier == 0x2013
}
```

替换为：

```swift
var isSingleWhiteDefaultCctProduct: Bool {
    guard companyIdentifier == 0x0A78, let productIdentifier else {
        return false
    }
    return productIdentifier == 0x2013 || productIdentifier == 0x24B1
}
```

这个改动会让以下现有属性自动覆盖两个 PID：

```swift
var defaultChangeControlPage: NodeChangeControlPage {
    isSingleWhiteDefaultCctProduct ? .singleWhite : .tunableWhite
}

var defaultAbsoluteCctRange: ClosedRange<UInt16> {
    isSingleWhiteDefaultCctProduct ? NodeAbsoluteCctRange.singleWhiteDefaultRange : NodeAbsoluteCctRange.standardDefaultRange
}
```

- [ ] **Step 3: 验证 SDK 特殊规则静态结果**

Run:

```bash
rg -n "productIdentifier == 0x2013|productIdentifier == 0x24B1|singleWhiteDefaultRange|standardDefaultRange" /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift
```

Expected: 同时看到 `productIdentifier == 0x2013` 和 `productIdentifier == 0x24B1`，并且 `defaultAbsoluteCctRange` 仍使用 `singleWhiteDefaultRange` / `standardDefaultRange`。

## Task 2: 更新 App 侧 PWM frequency 排除规则

**Files:**
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`

- [ ] **Step 1: 写入变更前静态检查，确认 PWM 排除规则尚未覆盖 `0x24B1`**

Run:

```bash
rg -n "supportPwmFrequency|0x2013|0x24B1" SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected: 在 `supportPwmFrequency` 附近只看到 `0x2013`，看不到 `0x24B1`。这说明当前检查会失败于新需求。

- [ ] **Step 2: 修改 PWM 排除条件**

在 `SunSmart/Common/Data/MeshNetwork+SunSmart.swift` 的 `supportPwmFrequency` 中将当前实现：

```swift
if companyIdentifier == 0x0A78 && pid == 0x2013 {
    return false
}
```

替换为：

```swift
if companyIdentifier == 0x0A78 && (pid == 0x2013 || pid == 0x24B1) {
    return false
}
```

保留下方已有 `switch pid` 排除列表，不修改其他 PID。

- [ ] **Step 3: 验证 App 侧 PWM 排除规则静态结果**

Run:

```bash
rg -n "companyIdentifier == 0x0A78 && \\(pid == 0x2013 \\|\\| pid == 0x24B1\\)|case 0x0031" SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected: 看到新的 `0x2013 || 0x24B1` 条件，且原有 `switch pid` 排除列表仍存在。

## Task 3: 验证 Device Parameter Settings 继续复用 SDK 默认值

**Files:**
- Inspect: `SunSmart/Main/Device/Parameter/Controller/DeviceParameterSettingsController.swift`
- Inspect: `SunSmart/Main/Device/Parameter/View/DeviceParameterSettingsViewCell.swift`

- [ ] **Step 1: 验证参数页默认值来源未被硬编码覆盖**

Run:

```bash
rg -n "defaultChangeControlPageForSelection|defaultCctRangeDataForSelection|changeControlPageMessageForSelection|isSingleWhiteDefaultCctProduct" SunSmart/Main/Device/Parameter/Controller/DeviceParameterSettingsController.swift
```

Expected: 看到 `defaultChangeControlPageForSelection` 使用 `devices.first?.defaultChangeControlPage`，`defaultCctRangeDataForSelection` 使用 `devices.first?.defaultAbsoluteCctRange`，特殊 Details 文案使用 `isSingleWhiteDefaultCctProduct`。

- [ ] **Step 2: 验证 UI 选项文案仍由默认值参数驱动**

Run:

```bash
rg -n "configure\\(value: NodeChangeControlPage, enabled: Bool, defaultValue: NodeChangeControlPage|Single White|Tunable White|Default" SunSmart/Main/Device/Parameter/View/DeviceParameterSettingsViewCell.swift
```

Expected: 看到 `configure` 接收 `defaultValue`，并在 `singleWhiteButton` / `tunableWhiteButton` 文案中只给默认项添加 `(Default)`。

不需要修改这两个文件；如果静态结果不符合预期，先停止并重新检查最近的 UI 改动，避免把默认值规则分散到 View 层。

## Task 4: 构建验证

**Files:**
- Verify: `SunSmart.xcworkspace`
- Verify: 本地 Swift Package `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`

- [ ] **Step 1: 检查改动范围**

Run:

```bash
git status --short
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk status --short
```

Expected: App 仓库只修改 `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`；SDK 仓库只修改 `Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift`。如果看到无关文件，确认不是本任务引入后不要改动。

- [ ] **Step 2: 运行 SunSmart iOS 构建**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 输出包含 `** BUILD SUCCEEDED **`。若失败，优先处理与本次两处 Swift 修改直接相关的编译错误；不要顺手处理无关 warning。

- [ ] **Step 3: 最终静态确认两个 PID 的完整覆盖**

Run:

```bash
rg -n "0x24B1|0x2013|isSingleWhiteDefaultCctProduct|supportPwmFrequency" /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected: SDK 特殊默认值判断和 App PWM 排除判断都同时包含 `0x2013` 与 `0x24B1`。

## Task 5: 提交检查点

**Files:**
- Commit scope: SDK 仓库改动
- Commit scope: App 仓库改动

- [ ] **Step 1: 提交前检查 diff**

Run:

```bash
git diff -- SunSmart/Common/Data/MeshNetwork+SunSmart.swift
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk diff -- Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift
```

Expected: 每个仓库都只有一个小范围条件判断变更。

- [ ] **Step 2: 根据用户要求决定是否提交**

当前用户只要求规划和后续实现，未要求自动 commit。执行实现时如果用户要求 commit，再分别提交：

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk add Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk commit -m "fix: include 24B1 in cct defaults"
git add SunSmart/Common/Data/MeshNetwork+SunSmart.swift
git commit -m "fix: hide pwm for 24B1 cct devices"
```

Expected: commit message 不包含 `codex` 相关内容。

## Self-Review

| 检查项 | 结果 |
| --- | --- |
| Spec 覆盖 | Task 1 覆盖两个 PID 的 `Single White` 和 `2700K...5000K` 默认值；Task 2 覆盖 PWM 隐藏；Task 3 覆盖 Details 文案和 UI 默认文案继续复用 SDK 特殊判断；Task 4 覆盖构建验证 |
| Placeholder scan | 无 `TBD`、`TODO`、未定义函数或“稍后实现”类占位描述 |
| Type consistency | 使用现有 `Node.isSingleWhiteDefaultCctProduct`、`Node.defaultChangeControlPage`、`Node.defaultAbsoluteCctRange`、`NodeChangeControlPage`、`NodeAbsoluteCctRange` 名称，未引入新类型 |
| Scope check | 只修改 SDK 默认值判断和 App PWM 支持判断，不触碰数据库、云同步、本地化或 UI 布局 |
