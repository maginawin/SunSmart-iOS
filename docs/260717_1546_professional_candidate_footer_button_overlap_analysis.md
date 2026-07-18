# Professional Mode Candidate Device List 底部按钮覆盖问题分析与修复计划

## 状态

- 结论：问题真实存在。
- 当前阶段：只完成代码与 Git 历史分析，尚未修改业务代码。
- 待确认：采用“单一入口统一渲染底部按钮可见性”的推荐方案后再实施。

## 问题范围

入口为 `Site > Space > Add Device > Professional Mode > Candidate Device List`。

问题发生在 `DeviceAddCandidateDeviceListView` 的底部区域：

- `Add Selected` 是 `DeviceAddBottomView` 自带的批量添加按钮。
- 另一个按钮是 Candidate Device List 自己叠加到 footer 上的 revoke 按钮。
- 两个按钮都位于 footer 右侧并垂直居中，因此同时显示时会发生覆盖。

该 Candidate view 只由 `DeviceAddProfessionalModeController` 创建，但同一源文件同时编译进 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个品牌 target。iPhone 使用底部弹窗，iPad 使用嵌入式 Candidate 列表，共享同一套按钮状态代码。

## 当前状态流

原有交互语义是：

| 场景 | Add Selected | Revoke |
| --- | --- | --- |
| 正在查找设备 | 隐藏 | 显示 |
| 暂停或停止查找设备 | 显示 | 隐藏 |
| 虚拟目标禁止批量选择 | 隐藏 | 由查找状态决定 |

当前代码仍保留了这套正确判断：

1. `state` 为 scanning，且当前确实在刷新设备时，revoke 显示。
2. `Add Selected` 根据 revoke 的显示状态做相反切换。

但同一轮状态更新随后还会调用 footer 的数量与批量控件刷新逻辑。该逻辑调用 `setBatchControlsHidden(false)` 时，会把 `Add Selected` 无条件重新显示。因此最终状态变成：

1. 扫描状态刷新先隐藏 `Add Selected`，显示 revoke。
2. footer 刷新再次显示 `Add Selected`。
3. 两个按钮同时存在于右侧同一区域，形成覆盖。

`state`、`isRefresh`、`candidateDevices` 等多个属性更新都会按“先刷新 UI、再刷新 footer”的顺序触发这条覆盖链，因此不是偶发的 Auto Layout 问题，而是稳定的可见性状态冲突。

## 回归历史

Git 历史与“最早版本正常”的描述一致：

1. 2025-07-08，提交 `60f20d12` 已实现 `Add Selected` 与 revoke 的互斥显示。
2. 2025-09-02，提交 `2912f9a3` 扩展了 light sensing 场景的查找状态判断，但仍保持按钮互斥。
3. 2026-06-04，提交 `3a87810c` 为虚拟 Battery/AC Power Switch 等目标增加批量选择控件隐藏能力：
   - `DeviceAddBottomView` 新增整组隐藏方法，其中包含 `Add Selected`。
   - Candidate view 的 footer 刷新开始调用该方法。
   - 当“不需要隐藏整组批量控件”时，该方法会把 `Add Selected` 重新显示，覆盖扫描态已有判断。

因此，回归根因不是扫描状态没有同步，也不是两个按钮约束写错；根因是 2026-06-04 后出现了两个相互独立的可见性写入点，并且后执行的通用批量控件刷新丢失了“正在查找设备”这一维状态。

## 方案比较

### 方案 A：Candidate view 内统一计算并渲染 footer 可见性（推荐）

将“虚拟目标是否允许批量选择”和“当前是否正在查找设备”两个条件合并，由一个 footer 状态刷新入口统一决定：

- 左侧 Select All 控件仍只受虚拟目标批量选择规则控制。
- `Add Selected` 同时受批量选择规则和查找状态控制。
- revoke 只受查找状态控制，并继续保留现有 enabled 逻辑。
- 删除或停止在其他刷新函数中单独写入同一按钮的隐藏状态。

优点：状态来源唯一，覆盖所有现有触发入口，保留虚拟目标规则，后续新增 footer 刷新不容易再次覆盖。

改动范围：预计只修改 `SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift`，不改文案、资源、target 配置、依赖或 SDK。

### 方案 B：修改 `DeviceAddBottomView.setBatchControlsHidden`

让共享方法不再控制 `Add Selected`，由各页面单独处理。

缺点：该共享方法目前被 Classic 和 Candidate flow 用于隐藏完整批量操作；改变其语义容易让虚拟目标下的 `Add Selected` 意外出现，并影响其他调用方。风险大于本问题所需范围。

### 方案 C：调整刷新调用顺序

保证扫描状态刷新最后执行，以最后一次写入覆盖 footer 刷新结果。

缺点：依赖调用顺序，`state`、`isRefresh`、设备数组、分类切换等入口较多，容易遗漏，后续维护时仍会回归。只压住表象，没有消除双写根因。

## 推荐修复计划

1. 在 `DeviceAddCandidateDeviceListView` 中定义唯一的“正在查找设备”判断，沿用现有语义，不改变 manual、RSSI range、motion sensing、light sensing 的行为边界。
2. 将 footer 的按钮可见性集中到一个刷新入口：
   - 查找中：隐藏 `Add Selected`，显示 revoke。
   - 暂停或停止：显示 `Add Selected`，隐藏 revoke。
   - 虚拟目标模式：继续隐藏批量选择相关控件，不能因本次修复重新开放批量添加。
3. 清理同一 view 内对 `Add Selected.isHidden` 的重复写入，避免两个刷新函数再次互相覆盖；不修改共享 `DeviceAddBottomView` 的公开语义。
4. 做状态矩阵验证：
   - 普通 Space/Group 目标：开始、暂停、恢复、停止查找。
   - Candidate 列表为空与已有候选设备两种情况。
   - manual、RSSI range、motion sensing、light sensing 四种 Professional Mode。
   - Battery/AC Power Switch、Emergency Controller、Dongle 等虚拟目标，确认批量选择仍被隐藏。
   - iPhone 底部弹窗为主要验收路径；同时核对 iPad 共享 view 不出现双按钮。
5. 运行差异与格式检查，并按项目规则使用 iPhoneOS `xcodebuild` 验证 `SunSmart`。由于该 Swift 文件属于四个品牌 target，若主 target 通过后仍有 target 条件差异，再补充其余品牌 target 编译验证。

## 验收标准

- Candidate Device List 正在查找设备时，右侧只显示 revoke，不显示 `Add Selected`。
- 停止查找设备后，右侧只显示 `Add Selected`，不显示 revoke。
- 暂停/恢复仍遵循现有产品语义，不引入新的按钮跳变。
- 两个按钮在任何状态下都不会同时显示。
- 虚拟目标下已有的单设备添加与批量控件隐藏规则保持不变。
- Classic Mode、Professional 主列表、设备筛选、添加流程、文案与本地化均不发生无关变化。

## 本轮未执行事项

- 未修改业务代码。
- 未创建提交。
- 未进行构建或真机交互验收；这些将在方案确认并实施后完成。
