# Space Trigger Zone Add to Zone UI 修复记录

## 目标

以 Proximity Profile Group 的 Path Sequence - Trigger Zone 页面为布局基准，修复 Space - More - Trigger Zone 中 Add to Zone 的 UI 问题。本次不修改设备筛选、添加、识别、保存或 Mesh 同步功能。

## 代码确认

- Group Path Sequence、Group Trigger Zone 和 Space Trigger Zone 共用 `GroupPathSequenceDeviceAddView`。
- Space Trigger Zone 通过 `SpacePathTriggerZoneController` 对共用弹窗启用 Space 专用的 Group 筛选与 Proximity Lighting 提示。
- Group Path Sequence 和 Group Trigger Zone 使用 `.fixedBase` 高度策略；Space Trigger Zone 使用 `.dynamicSelected` 高度策略。

因此，Space - More - Trigger Zone 没有使用另一套 Add to Zone 弹窗类，而是对共用弹窗做了专用配置。

## 根因

### 未选中 Zone

`canAddDevice = false` 会让三种添加模式显示 1、2、3 步骤引导。切换模式后，Space 控制器会重新同步筛选配置，而 Trigger Add 和 Manually Add 的配置方法会直接把 Group 筛选控件设为可见，覆盖引导态的显隐结果。由于引导层背景透明，`All eligible groups` 等控件会与步骤引导同时出现。

Space 当前高度策略只读取当前模式的首选高度。三种步骤文案的布局结果不完全一致时，切换模式会触发父弹窗高度变化。

### 选中 Zone

Space Quick Add 比 Group Trigger Zone 多出 `Only devices from proximity lighting groups will be detected` 提示，但仍沿用普通 Quick Add 的基础高度和按钮垂直中心。英文提示换成两行后，会侵入 Start/Pause 按钮区域。

Trigger Add、Manually Add 与 Quick Add 分别上报自身高度，Space 父弹窗按当前模式切换高度，导致三种模式之间不稳定。

## 修复设计

- Space 高度策略改为同时读取 Quick Add、Trigger Add、Manually Add 的首选高度，并始终采用三者最大值。
- 未选 Zone 时，三种模式均以步骤引导的最大高度为准，切换模式不改变弹窗高度。
- 选中 Zone 时，Space Quick Add 为双筛选和提示预留 186pt 内容高度；Start/Pause、Stop 和状态文字的中心线下移 20pt，避开顶部提示并保留底部说明空间。
- Trigger Add 和 Manually Add 的 Space 筛选配置必须服从当前引导态；未选 Zone 时不得重新显示 Group 筛选或设备内容。
- Manually Add 主动展开多行设备时仍允许弹窗按既有规则增高；普通三模式切换采用统一基础高度。
- Group Sequence 与 Group Trigger Zone 继续使用 `.fixedBase`，不改变其现有布局和功能。

## 验证范围

- 聚焦合同测试覆盖：Space 三模式统一高度、引导态显隐、Quick Add 提示避让、Group/Space 策略隔离。
- 对四个品牌 scheme 执行 generic iPhoneOS 无签名构建，检查共享源码对所有 target 的编译影响。
- 真机需要继续验证英文和简体中文下的未选/已选 Zone、三模式往返、Quick Add Start/Pause/Stop 以及 Manually Add 展开状态。构建与源码合同不能替代实际布局验收。

## 验证结果

- `GroupPathSequenceDeviceAddViewContractTests`：先失败于 Space 高度仍依赖当前模式，完成修复后通过。
- `PathTopologyPersistenceContractTests`：通过。
- `DeviceNameFilterExpansionContractTests`：通过。
- `git diff --check`：通过。
- `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 的 generic iPhoneOS Debug 无签名构建：全部通过。
- 当前环境未检测到连接的真机，尚未完成英文、简体中文实际界面与交互布局验收。
