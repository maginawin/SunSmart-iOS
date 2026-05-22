# Scene CCT Device Range Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复场景同步中混合色温范围设备的失败判定，让支持 CCT 的设备按自身范围保存，不支持 CCT 的设备跳过色温项。

**Architecture:** 在场景同步数据层增加设备级场景目标与设备级比较规则。消息生成、待同步判定、同步成功判定都复用同一规则，避免发送值、设备缓存值和比较目标不一致。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、Xcode workspace `SunSmart.xcworkspace`、scheme `SunSmart`。

---

## 文件结构

- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
  - 在现有 `SceneExecuteData` extension 中新增设备级目标和比较 helper。
  - 修改 `Group.getNeedSyncDataNodes(scene:)`，用设备级比较判断是否需要同步。
- Modify: `SunSmart/Common/Data/Node+MessageHandles.swift`
  - 修改 `Scene.getSyncMessageHandles(node:data:)`，发送前先计算设备级目标。
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  - 修改 `DeviceOperationType.isSuccessful` 的 scene 配置成功判定，使用设备级比较。
- Verification only: `SunSmart.xcworkspace`
  - 使用指定 xcodebuild 命令验证编译。

本工程当前未发现单元测试 target，本计划使用小范围 helper 降低风险，并以编译验证加真实/模拟 Mesh 场景手动回归作为验收。

## Task 1: 增加设备级场景目标和比较规则

**Files:**
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`

- [ ] **Step 1: 定位现有扩展**

Run: `rg -n "extension SceneExecuteData|func getNeedSyncDataNodes\\(scene" SunSmart/Common/Data/MeshNetwork+SunSmart.swift`

Expected: 看到 `getNeedSyncDataNodes(scene:)` 和 `extension SceneExecuteData` 的位置。

- [ ] **Step 2: 在 `extension SceneExecuteData` 中加入 helper**

在 `SceneExecuteData.cctRange` 后加入以下代码：

```swift
    /// 当前场景数据应用到指定设备时的目标值。
    /// 支持 CCT 的设备按自身有效色温范围夹紧；不支持 CCT 的设备跳过色温项。
    func deviceTarget(for node: Node) -> SceneExecuteData {
        let data = SceneExecuteData(
            sceneNumber: sceneNumber,
            isOn: isOn,
            lightness: lightness,
            cct: node.effectiveSupportCct ? node.clampEffectiveCct(cct) : cct,
            lightControlData: lightControlData
        )
        data.hue = hue
        data.saturation = saturation
        data.state = state
        return data
    }

    /// 判断设备缓存的场景数据是否已达到组场景在该设备上的实际目标。
    /// 不支持 CCT 的设备只比较场景、开关、亮度和状态，不让 CCT 字段影响同步结果。
    func isSynced(with groupSceneData: SceneExecuteData, for node: Node) -> Bool {
        let target = groupSceneData.deviceTarget(for: node)
        guard sceneNumber == target.sceneNumber,
              isOn == target.isOn,
              lightness == target.lightness,
              state == target.state else {
            return false
        }
        guard node.effectiveSupportCct else {
            return true
        }
        return cct == target.cct
    }
```

- [ ] **Step 3: 编译检查 helper 签名**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 如果只完成 Task 1，编译应通过，或只出现与本改动无关的既有 warning。

- [ ] **Step 4: Commit**

```bash
git add SunSmart/Common/Data/MeshNetwork+SunSmart.swift
git commit -m "fix: add device scene sync target"
```

## Task 2: 场景同步消息使用设备级目标

**Files:**
- Modify: `SunSmart/Common/Data/Node+MessageHandles.swift`

- [ ] **Step 1: 修改 `Scene.getSyncMessageHandles(node:data:)`**

将函数开头的 lightness/cct 计算替换为设备级目标。目标函数主体应保持如下形态：

```swift
    func getSyncMessageHandles(node: Node, data: SceneExecuteData) -> [MeshMessageHandle] {
        var messageHandles: [MeshMessageHandle] = []
        // 设备是否支持场景model及亮度model
        if let sceneSetupModel = node.sceneSetupModel {
            // 设备是否支持色温model
            let targetData = data.deviceTarget(for: node)
            let lightness = targetData.lightness
            if let ctlModel = node.ctlModel, node.effectiveSupportCct {
                messageHandles.append(MeshMessageHandle(message: LightCTLSet(lightness: lightness, temperature: targetData.cct, deltaUV: 0, transitionTime: .immediate, delay: 0), model: ctlModel))
            }else if let lightnessModel = node.lightnessModel { // 不支持色温则只设置亮度
                messageHandles.append(MeshMessageHandle(message: LightLightnessSet(lightness: lightness, transitionTime: .immediate, delay: 0), model: lightnessModel))
            }else if let onoffModel = node.onoffModel { // 不支持亮度
                messageHandles.append(MeshMessageHandle(message: GenericOnOffSet(lightness > 0), model: onoffModel))
            }
            // 保存场景
            if messageHandles.count > 0 {
                messageHandles.append(MeshMessageHandle(message: SceneStore(self.number), model: sceneSetupModel))
            }
        }
        return messageHandles
    }
```

- [ ] **Step 2: 检查没有残留旧变量**

Run: `rg -n "let cct = node.clampEffectiveCct\\(UInt16\\(data.cct\\)\\)" SunSmart/Common/Data/Node+MessageHandles.swift`

Expected: 无输出。

- [ ] **Step 3: 编译验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds。

- [ ] **Step 4: Commit**

```bash
git add SunSmart/Common/Data/Node+MessageHandles.swift
git commit -m "fix: clamp scene cct per device before sync"
```

## Task 3: 待同步判定使用设备级比较

**Files:**
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`

- [ ] **Step 1: 修改 `Group.getNeedSyncDataNodes(scene:)` 中的同步分支**

将现有直接比较：

```swift
if let nodeSceneData = $0.sceneExecuteDatas.first(where: { $0.sceneNumber == scene.number }) {
    return !(nodeSceneData == sceneData)
}
return true
```

替换为：

```swift
if let nodeSceneData = $0.sceneExecuteDatas.first(where: { $0.sceneNumber == scene.number }) {
    return !nodeSceneData.isSynced(with: sceneData, for: $0)
}
return true
```

- [ ] **Step 2: 静态确认待删除分支未被修改**

Run: `sed -n '1074,1105p' SunSmart/Common/Data/MeshNetwork+SunSmart.swift`

Expected: `sceneData.state == .waitDelete` 分支仍按 `sceneSetupModel` 和 `sceneExecuteDatas` 判断待删除节点。

- [ ] **Step 3: 编译验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds。

- [ ] **Step 4: Commit**

```bash
git add SunSmart/Common/Data/MeshNetwork+SunSmart.swift
git commit -m "fix: compare scene sync per device"
```

## Task 4: 同步成功判定使用设备级比较

**Files:**
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`

- [ ] **Step 1: 修改 `.configuration(... .scene(...))` 成功判定**

将 `DeviceOperationType.isSuccessful` 中 scene 配置分支替换为：

```swift
            case .scene(let sceneId, let sceneData):
                guard let sceneData = sceneData, let nodeScene = node.sceneExecuteDatas.first(where: { $0.sceneNumber == sceneId }) else {
                    return false
                }
                guard nodeScene.isSynced(with: sceneData, for: node) else {
                    let target = sceneData.deviceTarget(for: node)
                    print("scene\(sceneData.sceneNumber) target: lightness \(target.lightness) cct \(target.cct)")
                    print("scene\(nodeScene.sceneNumber) real: lightness \(nodeScene.lightness) cct \(nodeScene.cct)")
                    return false
                }
                return true
```

- [ ] **Step 2: 确认删除 scene 判定不变**

Run: `sed -n '180,265p' SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`

Expected: `.delete(... .scene(...))` 仍通过 `!node.sceneExecuteDatas.contains(where:)` 判定删除成功。

- [ ] **Step 3: 编译验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds。

- [ ] **Step 4: Commit**

```bash
git add SunSmart/Main/Space/Model/SyncDevicesCellModel.swift
git commit -m "fix: validate scene sync per device"
```

## Task 5: 端到端验证

**Files:**
- No source edits expected.

- [ ] **Step 1: 全量编译验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds。

- [ ] **Step 2: 手动验证混合 CCT 范围场景**

准备一个组，组内至少包含：

- A：`effectiveCctRange == 2700...6500`
- B：`effectiveCctRange == 2700...5000`

操作：

1. 进入场景 Settings。
2. 将组场景色温设置为 `6500K`。
3. SAVE 并进入 Sync device(s)。
4. 等待同步完成。
5. 返回后再次进入该场景的 Sync device(s)。

Expected:

- A 设备同步成功，设备场景缓存 CCT 为 `6500K`。
- B 设备同步成功，设备场景缓存 CCT 为 `5000K`。
- B 不再持续显示 Failure。
- 再次进入 Sync device(s) 时，B 不再因为 `5000K != 6500K` 被列为待同步。

- [ ] **Step 3: 手动验证不支持 CCT 的设备**

准备一个只支持亮度或开关、不支持 CCT 的设备加入场景组。

操作：

1. 设置同一组场景色温为 `6500K`。
2. SAVE 并同步。

Expected:

- 该设备发送亮度或开关消息后执行 `SceneStore`。
- 不发送 `LightCTLSet`。
- 同步成功判定不比较 CCT 字段。
- 该设备不因为 CCT 字段显示 Failure。

- [ ] **Step 4: 最终状态检查**

Run: `git status --short`

Expected: working tree clean。
