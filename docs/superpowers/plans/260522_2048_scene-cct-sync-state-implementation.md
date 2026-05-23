# Scene CCT Sync State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让所有场景同步状态判断复用设备级 CCT 目标比较，避免 `Single White (DIM)` 设备或 CCT range 不同设备反复提示需要同步。

**Architecture:** 继续沿用上一轮新增的 `SceneExecuteData.deviceTarget(for:)` 和 `SceneExecuteData.isSynced(with:for:)`。本次只把遗漏的同步状态入口改到同一个比较函数，不新增数据模型、不改组场景保存语义。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、Xcode workspace `SunSmart.xcworkspace`。

---

## File Structure

- Modify: `SunSmart/Common/Data/Node+SyncData.swift`
  - 负责节点同步项计算。本次修复 `getNodeSyncSceneDatas(group:scene:)`，让 `Scene.needSyncGroups`、`Group.needSync`、`Node.needSyncGroupData` 的场景判断与 Sync device(s) 页面一致。
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift`
  - 负责 Emergency Fire 相关同步 cell 的成功判定。该文件仍有直接 `nodeScene == sceneData`，按一致性要求改为设备级比较。
- Verify only: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  - 已在上一轮修复为设备级比较，本计划只通过静态搜索确认没有回退。

---

### Task 1: 修复节点场景同步状态判断

**Files:**
- Modify: `SunSmart/Common/Data/Node+SyncData.swift`

- [ ] **Step 1: 打开目标函数确认旧逻辑**

Run:

```bash
sed -n '1288,1315p' SunSmart/Common/Data/Node+SyncData.swift
```

Expected: 看到 `getNodeSyncSceneDatas(group:scene:)` 中存在直接对象比较：

```swift
if data.state == .normal, sceneData == nil || !(sceneData! == data) {
    syncSceneData.append((scene, data))
}
```

- [ ] **Step 2: 改为设备级同步比较**

在 `SunSmart/Common/Data/Node+SyncData.swift` 中，将该判断替换为：

```swift
if data.state == .normal {
    guard let sceneData = sceneData else {
        syncSceneData.append((scene, data))
        return
    }
    if !sceneData.isSynced(with: data, for: self) {
        syncSceneData.append((scene, data))
    }
}
```

注意：

- `data` 是组场景数据。
- `sceneData` 是设备缓存的场景数据。
- `self` 是当前 `Node`。
- 不能把 `Single White (DIM)` 设备排除出场景同步；设备没有该场景时仍必须加入 `syncSceneData`。

- [ ] **Step 3: 静态确认旧比较已移除**

Run:

```bash
sed -n '1288,1318p' SunSmart/Common/Data/Node+SyncData.swift
```

Expected: 目标函数里不再出现 `sceneData! == data`。

- [ ] **Step 4: 编译验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: 提交**

Run:

```bash
git add SunSmart/Common/Data/Node+SyncData.swift
git commit -m "fix: compare node scene sync per device"
```

Expected: commit 成功。

---

### Task 2: 修复 Emergency Fire 同类直接比较

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift`

- [ ] **Step 1: 打开旧成功判定**

Run:

```bash
sed -n '100,118p' SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift
```

Expected: 看到 `.configuration(... .scene(...))` 分支中存在：

```swift
guard nodeScene == sceneData else {
    print("scene\(sceneData.sceneNumber) target: lightness \(sceneData.lightness) cct \(sceneData.cct)")
    print("scene\(nodeScene.sceneNumber) real: lightness \(nodeScene.lightness) cct \(nodeScene.cct)")
    return false
}
```

- [ ] **Step 2: 改为设备级成功判定**

将上述判断替换为：

```swift
guard nodeScene.isSynced(with: sceneData, for: node) else {
    let target = sceneData.deviceTarget(for: node)
    print("scene\(sceneData.sceneNumber) target: lightness \(target.lightness) cct \(target.cct)")
    print("scene\(nodeScene.sceneNumber) real: lightness \(nodeScene.lightness) cct \(nodeScene.cct)")
    return false
}
```

这让 Emergency Fire 同步入口与通用 Sync device(s) 入口使用同一场景比较语义。

- [ ] **Step 3: 静态确认文件内旧比较已移除**

Run:

```bash
rg -n "nodeScene == sceneData|sceneData\\.isSynced\\(with: sceneData" SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift
```

Expected:

- 不出现 `nodeScene == sceneData`。
- 不出现错误的自比较 `sceneData.isSynced(with: sceneData`。

- [ ] **Step 4: 编译验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: 提交**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift
git commit -m "fix: validate fire alarm scene sync per device"
```

Expected: commit 成功。

---

### Task 3: 最终一致性验证

**Files:**
- Verify only: `SunSmart/Common/Data/Node+SyncData.swift`
- Verify only: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- Verify only: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
- Verify only: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift`

- [ ] **Step 1: 搜索场景数据直接比较残留**

Run:

```bash
rg -n "nodeScene == sceneData|sceneData! == data|== data\\)" SunSmart/Common/Data/Node+SyncData.swift SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift
```

Expected: 不应出现本次相关的场景同步直接比较残留。若出现无关匹配，逐条确认不属于 `SceneExecuteData` 的同步状态或成功判定。

- [ ] **Step 2: 搜索设备级比较调用**

Run:

```bash
rg -n "isSynced\\(with:.*for:" SunSmart/Common/Data/Node+SyncData.swift SunSmart/Common/Data/MeshNetwork+SunSmart.swift SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift
```

Expected: 至少包含以下调用点：

- `Group.getNeedSyncDataNodes(scene:)`
- `Node.getNodeSyncSceneDatas(group:scene:)`
- `DeviceOperationType.isSuccessful`
- `EmerFireAlarmSyncCellModel` 的对应成功判定

- [ ] **Step 3: 最终编译验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 工作区状态检查**

Run:

```bash
git status --short
```

Expected: 无输出，表示工作区 clean。

- [ ] **Step 5: 手动验证记录**

当前环境无法真实操作 Mesh 设备。实现完成后需要在真机或实际 Mesh 环境验证：

1. A 原始支持 CCT，配置为 `Single White (DIM)`。
2. B 原始支持 CCT，配置为 `Tunable White (CCT)`。
3. B 已加入 Group 1，并已配置 S1。
4. 将 A 加入 Group 1。
5. 在 Sync device(s) 同步 Group 1 和 S1。
6. 预期 A 保存 S1 的亮度和开关，Group 1 与 S1 不再提示需要同步。
7. 再验证 A range `2700K...6500K`、B range `2700K...5000K`、组场景 `6500K` 的场景：A 保存 `6500K`，B 保存 `5000K`，Group 1 与 S1 不再提示需要同步。

