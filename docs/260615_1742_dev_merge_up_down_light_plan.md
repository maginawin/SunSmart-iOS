# dev 合并到 up-down-light 冲突处理计划

## 当前事实

- 当前分支：`up-down-light`
- 当前状态：工作区未处于 merge 中，`git status --short --branch` 显示 `up-down-light...origin/up-down-light [ahead 1]`
- 待合并分支：本地 `dev`
- merge base：`9aeaa1e504fc0d29f7f7e852e34a241ecc6c1351`
- 当前分支新增提交：`e1143d41 feat: up down light group page and command`
- `dev` 当前提交：`c14571dc Merge branch 'fix' into dev`
- 使用 `git merge-tree --write-tree --name-only HEAD dev` 预演，真实文本冲突只有 4 个文件：
  - `SunSmart.xcodeproj/project.pbxproj`
  - `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
  - `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
  - `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`

## 合并原则

1. 以 `dev` 为主线吸收后续修复，不回退 `dev` 已完成的 fast-add group sync、power switch 删除提示、Device Parameter filter、Space lights broadcast 等修复。
2. 保留 `up-down-light` 当前提交中与 Up/Down Light 相关的资源、控件、组控逻辑、vendor command、默认 CCT steps 读取逻辑。
3. 对冲突文件不要简单选择 ours/theirs。Swift 冲突的核心是两个功能在同一回调链路叠加，必须组合：
   - `dev` 的 add-to-group fast-add sync 批次管理保留。
   - `up-down-light` 的 `UpDownLightDefaultCctStepsReader.readAfterProvisioning` 接到 `dev` 的最终 add finish 流程里。
4. `project.pbxproj` 要同时保留 `dev` 新增的 Content Display 源文件引用，以及 `up-down-light` 新增的 Up/Down Light 源文件引用和 target membership。

## 冲突文件处理方案

### 1. `SunSmart.xcodeproj/project.pbxproj`

冲突原因：

- `up-down-light` 新增：
  - `DeviceLightControlPanelView.swift`
  - `DeviceUpDownRatioControlView.swift`
  - `UpDownLightView.swift`
- `dev` 新增或移动：
  - `ContentDisplaySwitchViewCell.swift`
  - `ContentDisplayControlStyleViewCell.swift`
- 两边都修改了 PBXBuildFile、PBXFileReference、PBXGroup、PBXSourcesBuildPhase 附近内容。

处理方案：

- 以自动合并结果为基础手动清理 conflict marker。
- 保留 `dev` 的 Content Display 两个 file reference 和四个 target 的 source build phase 记录。
- 保留 `up-down-light` 的 Up/Down Light 三个 Swift file reference，其中：
  - `DeviceLightControlPanelView.swift` 加入相关 target source build phase。
  - `DeviceUpDownRatioControlView.swift` 加入相关 target source build phase。
  - `UpDownLightView.swift` 按当前分支已有 target membership 保留。
- 检查 `SunSmart/Main/Device/View` group 下同时包含 Content Display 与 Up/Down Light 相关文件，不重复、不丢失。
- 处理后用 `rg -n "<<<<<<<|=======|>>>>>>>" SunSmart.xcodeproj/project.pbxproj` 确认无冲突标记。

### 2. `DeviceGroupDeferredSyncPlanner.swift`

冲突原因：

- `dev` 把 group add 后的同步模型升级为 fast-add sync：
  - 新增 `DeviceGroupFastAddSyncPlan`
  - 新增 `DeviceGroupFastAddSyncPlanner`
  - `DeviceGroupDeferredSyncPlanner.makePlan` 增加 `effectiveMemberCount`
  - 新增 verification operations，用于判断 group sync 是否失败
- `up-down-light` 在文件末尾新增 `UpDownLightDefaultCctStepsReader`，用于配网完成后读取支持 Up/Down Ratio Control 设备的默认 CCT steps，并写入 `node.upDownLightDefaultCctSteps`。

处理方案：

- 以 `dev` 版本为主体，完整保留 fast-add sync planner。
- 在文件末尾追加并保留 `UpDownLightDefaultCctStepsReader`。
- 确认 `UpDownLightDefaultCctStepsReader` 仍使用：
  - `supportsUpDownRatioControl`
  - `SunricherVendorGet(function: .upDownLightDefaultCctSteps)`
  - `.upDownLightDefaultCctSteps(let steps)`
  - 默认 fallback 为 `5`，仅当返回 `6` 时保存 `6`
- 不把 `UpDownLightDefaultCctStepsReader` 混入 `DeviceGroupFastAddSyncPlanner`，避免默认 CCT steps 读取和 group sync verification 互相耦合。
- 处理后用搜索确认两个 planner 都存在：
  - `DeviceGroupFastAddSyncPlanner`
  - `UpDownLightDefaultCctStepsReader`

### 3. `DeviceAddClassicModeController.swift`

冲突原因：

- `dev` 已移除旧的 `finishGroupDeferredSyncPlans` 路径，改为：
  - `prepareFastAddGroupSyncBatch(devices:)`
  - `registerFastAddGroupSyncPlan(_:)`
  - `resolveFastAddGroupSyncFailed(for:)`
  - `resetFastAddGroupSyncBatch()`
- `up-down-light` 在 `addFinish` 中把最终 callback 和通知包进 `UpDownLightDefaultCctStepsReader.readAfterProvisioning(devices:)`。

处理方案：

- 以 `dev` 版本为主体，保留 fast-add group sync 字段和 helper：
  - `fastAddGroupSyncPlans`
  - `failedFastAddGroupSyncNodeAddresses`
  - `fastAddGroupEffectiveMemberCount`
  - `prepareFastAddGroupSyncBatch`
  - `resetFastAddGroupSyncBatch`
  - `registerFastAddGroupSyncPlan`
  - `fastAddGroupSyncPlan`
  - `recordFastAddGroupSyncFailure`
  - `resolveFastAddGroupSyncFailed`
- 保留 `dev` 在 `appendMessagesBack` 中对 `DeviceGroupFastAddSyncPlanner.makePlan` 的调用。
- 保留 `dev` 在 `appendMessageSuccessBack` / `appendMessageFailedBack` / `addSuccess` 中对 fast-add sync 状态的判断。
- 修改 `addFinish`：不要恢复旧的 `finishGroupDeferredSyncPlans`；应在 `dev` 当前 add finish 最终动作外层加入 `UpDownLightDefaultCctStepsReader.readAfterProvisioning(devices: successList)`。
- `readAfterProvisioning` 完成后再执行：
  - `deviceStateCallback?(false)`
  - `deviceAddCallback?(addSuccessNodes)`
  - `space.deviceCount/luminairesCount/switchesCount` 更新与保存
  - space/device refresh notifications
  - `resetFastAddGroupSyncBatch()`
  - `finishBatteryPowerSwitchInitialBatteryReadsAndDisconnect()`
- 注意 Classic 的 callback 顺序当前分支是先 `deviceStateCallback` 后 `deviceAddCallback`；如果保留历史行为，继续使用 Classic 当前顺序。

### 4. `DeviceAddProfessionalModeController.swift`

冲突原因与 Classic 相同，但该文件使用 `addTarget` 判断 group/dongle 入口，且当前分支在 `addFinish` 中先 `deviceAddCallback` 后 `deviceStateCallback`。

处理方案：

- 以 `dev` 版本为主体，保留所有 fast-add group sync 相关字段、helper 和回调处理。
- 保留 `dev` 对 `case .group(let group) = self.addTarget` 的逻辑，不退回 `addToGroup`。
- 修改 `addFinish`：不要恢复旧的 `finishGroupDeferredSyncPlans`；应在 `dev` 当前 add finish 最终动作外层加入 `UpDownLightDefaultCctStepsReader.readAfterProvisioning(devices: successList)`。
- `readAfterProvisioning` 完成后再执行原本 Professional final actions：
  - `deviceAddCallback?(addSuccessNodes)`
  - `deviceStateCallback?(false)`
  - space count 更新与保存
  - notifications
  - `resetFastAddGroupSyncBatch()`
  - `finishBatteryPowerSwitchInitialBatteryReadsAndDisconnect()`
- 注意 Professional 的 callback 顺序保留为先 `deviceAddCallback` 后 `deviceStateCallback`。

## 非冲突但必须复核的路径

这些文件不会产生文本冲突，但属于合并后的语义风险点：

- `SunSmart/Main/Group/Controller/GroupViewController.swift`
  - 当前分支有 Up/Down ratio group control 与 vendor subscription 逻辑。
  - `dev` 没直接冲突，但合并后需要确认 group 页面仍能展示 Up/Down ratio 控件并发送命令。
- `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`
  - 当前分支有 Up/Down Light device page UI 和 CCT defaults 行为。
  - `dev` 未冲突，但合并后需要确认设备页初始化、CCT quick buttons、背景色行为不被覆盖。
- `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`
  - 除了解冲突，还要确认 `DeviceGroupFastAddSyncPlanner` 的 verification operations 不漏掉 Up/Down Light 相关 immediate handles。
- `SunSmart/Common/Data/Node+Capability.swift`
  - 当前分支的 `supportsUpDownRatioControl` 是 `UpDownLightDefaultCctStepsReader` 的 gate，合并后必须存在。
- `SunSmart/Common/Data/Node+SyncData.swift`
  - `dev` 侧 group sync 改动和当前分支 Up/Down 组控同步语义都可能依赖该文件，合并后需要搜索相关 case 是否都保留。
- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`
  - `dev` 新增 power switch 删除文案。
  - 当前分支若有 Up/Down Light 文案，合并后都要保留。

## 执行步骤

- [x] **Step 1：确认工作区干净**

运行：

```sh
git status --short --branch
```

预期：

- 只显示当前分支 ahead 信息。
- 无未提交业务改动。
- 如果计划文档尚未提交，会显示本计划文件；执行真实 merge 前先决定是否提交或暂存该文档。

- [x] **Step 2：开始合并**

运行：

```sh
git merge dev
```

预期：

- 出现 4 个冲突文件：
  - `SunSmart.xcodeproj/project.pbxproj`
  - `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
  - `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
  - `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`

- [x] **Step 3：先解 Swift planner 冲突**

处理：

- `DeviceGroupDeferredSyncPlanner.swift` 以 `dev` 的 fast-add sync planner 为主体。
- 文件末尾保留 `UpDownLightDefaultCctStepsReader`。

验证：

```sh
rg -n "DeviceGroupFastAddSyncPlanner|UpDownLightDefaultCctStepsReader|<<<<<<<|=======|>>>>>>>" SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift
```

预期：

- 能找到两个 planner/reader 名称。
- 找不到冲突标记。

- [x] **Step 4：解 Classic Add Device 冲突**

处理：

- 保留 `dev` 的 fast-add group sync 状态字段、helper、append message、success/failure callback。
- 在 `addFinish` 中用 `UpDownLightDefaultCctStepsReader.readAfterProvisioning(devices: successList)` 包住最终完成逻辑。
- 不恢复 `finishGroupDeferredSyncPlans` 旧路径。

验证：

```sh
rg -n "finishGroupDeferredSyncPlans|DeviceGroupFastAddSyncPlanner|UpDownLightDefaultCctStepsReader|resetFastAddGroupSyncBatch|<<<<<<<|=======|>>>>>>>" SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift
```

预期：

- 找不到 `finishGroupDeferredSyncPlans`。
- 能找到 `DeviceGroupFastAddSyncPlanner`、`UpDownLightDefaultCctStepsReader`、`resetFastAddGroupSyncBatch`。
- 找不到冲突标记。

- [x] **Step 5：解 Professional Add Device 冲突**

处理：

- 与 Classic 相同，但保留 Professional 的 `addTarget` 逻辑。
- 在 `addFinish` 中用 `UpDownLightDefaultCctStepsReader.readAfterProvisioning(devices: successList)` 包住最终完成逻辑。
- 保留 Professional 现有 callback 顺序。

验证：

```sh
rg -n "finishGroupDeferredSyncPlans|DeviceGroupFastAddSyncPlanner|UpDownLightDefaultCctStepsReader|resetFastAddGroupSyncBatch|<<<<<<<|=======|>>>>>>>" SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

预期：

- 找不到 `finishGroupDeferredSyncPlans`。
- 能找到 `DeviceGroupFastAddSyncPlanner`、`UpDownLightDefaultCctStepsReader`、`resetFastAddGroupSyncBatch`。
- 找不到冲突标记。

- [x] **Step 6：解 Xcode 工程冲突**

处理：

- 同时保留 Content Display 源文件和 Up/Down Light 源文件。
- 确认四个品牌 target 的 source build phase 没有丢掉新文件。

验证：

```sh
rg -n "ContentDisplaySwitchViewCell|ContentDisplayControlStyleViewCell|DeviceLightControlPanelView|DeviceUpDownRatioControlView|UpDownLightView|<<<<<<<|=======|>>>>>>>" SunSmart.xcodeproj/project.pbxproj
```

预期：

- 能找到上述 5 类文件引用。
- 找不到冲突标记。

- [x] **Step 7：全仓冲突标记检查**

运行：

```sh
rg -n "<<<<<<<|=======|>>>>>>>" .
```

预期：

- 无输出。

- [x] **Step 8：语义搜索检查**

运行：

```sh
rg -n "supportsUpDownRatioControl|upDownLightDefaultCctSteps|UpDownLightDefaultCctStepsReader|DeviceGroupFastAddSyncPlanner|power_switch_battery_delete_message|devicesSupportingFilter" SunSmart
```

预期：

- Up/Down Light capability、默认 CCT steps reader、fast-add planner、`dev` 新增文案/filter helper 都存在。

- [x] **Step 9：检查待提交文件**

运行：

```sh
git status --short
```

预期：

- 冲突文件已解决。
- Up/Down Light 资源和源文件保留。
- `dev` 新增文档/修复文件保留。

- [x] **Step 10：格式与构建验证**

运行：

```sh
git diff --check
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

预期：

- `git diff --check` 无输出。
- iPhoneOS build 成功。

## 人工回归建议

- Add Device Classic：添加支持 Up/Down Ratio Control 的灯到 group，确认配网完成后不会卡住 final callback，且设备会读取默认 CCT steps。
- Add Device Professional：同上，确认 `addTarget` 为 group 时 fast-add sync 和 Up/Down default CCT steps 读取都执行。
- Group control page：进入包含 Up/Down Light 的 group，确认 Up/Down ratio 控件仍显示并能发送命令。
- Device light page：进入 Up/Down Light 设备页，确认 UI 资源存在、quick buttons 与默认 steps 行为正常。
- Device Parameter Settings：确认 `dev` 的 Filter 能力过滤逻辑仍存在。
- Power Switch 删除入口：确认 `dev` 的 Battery/AC 删除提示文案仍存在。

## 风险点

- 最大风险不是文本冲突，而是把 `up-down-light` 的旧 deferred sync 路径恢复回来，覆盖 `dev` 的 fast-add sync 修复。
- `project.pbxproj` 冲突容易漏 target membership。构建能发现多数漏源文件问题，但仍要用搜索确认所有新增 Swift 文件都在工程里。
- `UpDownLightDefaultCctStepsReader` 是异步读取；必须保证最终通知和 disconnect 在 reader completion 之后执行，避免刚配网完成即刷新 UI 时默认 steps 还没落库。
- 如果 `readAfterProvisioning` 某个设备响应超时，会按当前实现 fallback 到 5；合并时不要改变这个 fallback 语义。
