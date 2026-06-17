# EFC Default Name Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 统一 Emergency Fire Controller 的虚拟和真实默认名称规则，确保同一 Space 内按 `EFCn` 选择最小未占用序号，并同步真实节点名称。

**Architecture:** 将 EFC 默认名称规则收敛在 `DeviceEmerFireStore`，由虚拟创建、真实添加、自动合并和 restore 共用。Classic / Professional Add Device 不直接改名，继续通过 shared store 生效，避免重复补丁。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、SunSmart iOS workspace。

---

## File Structure

- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData.swift`
  - 负责 EFC 本地配置聚合、默认名称生成、真实节点合并、绑定和 restore。
- No change: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
  - 通用节点命名保持不变，避免影响非 EFC 设备。
- No change: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
  - 通过 `DeviceEmerFireStore.ensureDevice` / `bind` 间接受益。
- No change: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
  - 通过 `DeviceEmerFireStore.ensureDevice` / `bind` 间接受益。
- No change: project resources, localization, target configuration, dependencies.

## Task 1: 收敛 EFC 默认名生成和节点同步

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData.swift`

- [ ] **Step 1: 更新默认名 base**

在 `DeviceEmerFireStore.nextDefaultName(space:)` 和 private `nextDefaultName(in:)` 中，将 base 从 `EFC ` 改为 `EFC`。

Expected behavior:

- 空 Space 返回 `EFC1`。
- 已有 `EFC1` 返回 `EFC2`。
- 不把 `EFC 1` 或 `FEC1` 当作目标格式占用规则。

- [ ] **Step 2: 让绑定已有虚拟 EFC 时同步真实 node.name**

在 `DeviceEmerFireStore.bind(_:to:in:)` 中，保存 EFC 本地记录前同步真实节点名称。

Required behavior:

- `target.bindNodeAddress = node.primaryUnicastAddress`
- `node.name = target.name`
- `node.save()`
- `target.isSynced = false`
- `save(target)`

这样 LINK 到已有虚拟 `EFC1` 时，新真实节点名称也变为 `EFC1`。

- [ ] **Step 3: 让自动补真实 EFC 本地记录时使用统一 EFCn**

在 `mergeRealEmergencyControllers(...)` 的新建记录分支中，不再使用 `node.name ?? nextDefaultName(in: devices)` 作为 EFC 业务名。

Required behavior:

- 先通过 `nextDefaultName(in: devices)` 生成 `let name`。
- 新 `DeviceEmerFireData.name` 使用 `name`。
- 同步 `node.name = name` 并 `node.save()`。
- repository 保存后 append 到 `devices`，保证同一次循环内后续真实 EFC 会看到前一个名称占用。

- [ ] **Step 4: 让 restore 兜底和旧记录恢复同步真实 node.name**

在 `restoreDevice(replacing:with:in:)` 中，确定 `target` 后同步新节点名称。

Required behavior:

- 如果找到旧记录，保留 `target.name`，同步 `newNode.name = target.name`。
- 如果没有旧记录，`DeviceEmerFireData.default(space:)` 已生成统一 `EFCn`，同步 `newNode.name = target.name`。
- 保存 `newNode`。
- 保持 `target.bindNodeAddress = newNode.primaryUnicastAddress` 和 `target.isSynced = false`。

- [ ] **Step 5: 静态检查共享入口**

检查以下调用点仍然只通过 shared store 生效，不新增入口级命名逻辑：

- `DeviceAddClassicModeController`: `ensureDevice(for:in:)`、`bind(_:to:in:)`
- `DeviceAddProfessionalModeController`: `ensureDevice(for:in:)`、`bind(_:to:in:)`
- `DeviceRestoreViewController`: `restoreDevice(replacing:with:in:)`

Expected: 不修改这些 controller。

- [ ] **Step 6: Run diff check**

Run:

`git diff --check`

Expected: no output.

- [ ] **Step 7: Build iPhoneOS**

Run:

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: build succeeds.

- [ ] **Step 8: Commit implementation**

Stage only the intended implementation file and plan document if not already committed.

Run:

`git status --short`

Expected before commit:

- Modified implementation file.
- Existing unrelated `SunSmart.xcodeproj/project.pbxproj` may remain unstaged.

Commit message:

`fix: unify efc default naming`

## Self-Review

- Spec coverage: covers `EFCn` format, Space-level EFC record occupancy, virtual creation, real add, LINK, restore, and node.name synchronization.
- Placeholder scan: no TODO/TBD placeholders.
- Type consistency: all referenced methods exist in `DeviceEmerFireStore`; no new public API is required.
- Scope check: one shared model file handles the behavior; no unrelated controller or project configuration changes are planned.
