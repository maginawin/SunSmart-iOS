# EFC Visitor Permissions Design

## 目标

当当前 Space 访问角色是 Visitor 时，只限制 EFC 设备页内明确列出的入口：

- 真实 EFC 设备页右上角菜单仅保留 `Information`。
- 真实 EFC 设备页保留 `Identify` 可用。
- 真实 EFC 设备页的 `Fire Alarm Mock Button`、`Power Loss Mock Button`、`Restore Mock Button` 点击后显示 `Insufficient permissions` Toast 并停止执行。
- 虚拟 EFC 设备页右上角菜单没有可选项。
- 虚拟 EFC 设备页的同 3 个 Mock Button 点击后显示 `Insufficient permissions` Toast 并停止执行。

本轮不修改全局 Visitor 权限模型，也不限制 EFC 页面其它未点名入口。

## 当前代码事实

- 真实和虚拟 EFC 设备页共用 `EmerFireAlarmMonitorVC`。
- 右上角菜单逻辑在 `EmerFireAlarmMonitorRouting.swift`，真实设备走 `moreClick()`，虚拟设备走 `showUnlinkedVirtualEmergencyFireControllerMenu()`。
- 底部 4 个圆形操作按钮由 `EmerFireAlarmMoniView` 承载，顺序是 `Identify`、`Mock Fire Alarm`、`Mock Power Loss`、`Mock Restore`。
- 3 个 Mock action 当前分别落到 `mockFireAlarmAction()`、`mockPowerLossAction()`、`mockRestoreAction()`。
- `SpaceData.deviceOperates` 对 Visitor 仍返回 `.control`，但 EFC 配置和删除依赖 `.edit` / `.delete`，因此本需求应在 EFC 设备页内做局部权限判断。
- `Status & Settings` 展开区目前没有可操作行；header 里的状态图标 stack 设置了 `isUserInteractionEnabled = false`，table 只展示状态内容，没有 `didSelectRowAt`。
- `Insufficient permissions` 已存在英文和简体中文本地化 key，可直接复用。

## 方案选择

采用方案 A：在 EFC Monitor 页增加 EFC 专用 Visitor 判断，只拦截本需求列出的菜单项和 3 个 Mock Button。

不采用修改 `canOperateEmergencyActions` 的方案，因为这会影响更多 EFC 控制路径。

不采用修改 `SpaceData.deviceOperates` 的方案，因为这会影响全局设备、组、场景等 Visitor 控制能力。

## 设计

### Visitor 判断

在 `EmerFireAlarmMonitorViewModel` 或 `EmerFireAlarmMonitorVC` 增加一个只读判断，例如 `isEffectiveVisitor`：

- 数据来源：`space?.permission == .visitor`
- 不改变 `canConfigureDevice` 和 `canOperateEmergencyActions` 的现有语义。
- 只供 EFC 设备页菜单和 Mock action guard 使用。

### 真实 EFC 设备页菜单

在 `EmerFireAlarmMonitorRouting.moreClick()` 中增加 Visitor 分支：

- Visitor：仅构建 `Information` 菜单项。
- Owner / Editor：保留现有 `Edit`、`Delete`、`Information`、`Refresh` 条件逻辑。
- `Information` 点击仍进入现有 `DeviceInformationViewController`，继续使用当前 EFC group 文案覆盖和 scene section 隐藏逻辑。

### 虚拟 EFC 设备页菜单

在 `showUnlinkedVirtualEmergencyFireControllerMenu()` 中增加 Visitor 分支：

- Visitor：不展示菜单项。实现上优先直接 return，不弹空白菜单。
- Owner / Editor：保留现有 `Edit` / `Delete` 条件逻辑。

### Mock Button 权限

在 `EmerFireAlarmMonitorVC` 中新增共享 guard，例如 `guardVisitorCanUseMockAction()`：

- Visitor：显示 `"Insufficient permissions".localizedString`，返回 `false`。
- 非 Visitor：返回 `true`。

将该 guard 放在 3 个 Mock action 的第一层：

- `mockFireAlarmAction()`
- `mockPowerLossAction()`
- `mockRestoreAction()`

这样 Visitor 点击 Mock Button 时会优先得到权限提示，不会继续触发“未关联设备”“未关联组”“failed”等后续业务提示，也不会发送 mesh 命令。

`Identify` 不增加 Visitor 限制，保持现有设备识别流程。

## 非目标

- 不修改 Space / Device / Group / Scene 的全局 Visitor 权限模型。
- 不限制关联组卡片点击、Status & Settings 展开/收起、状态展示刷新。
- 不改 EFC Edit、Delete、Sync、Add Device、Bind、Restore 流程语义。
- 不新增 Auth 信息。
- 不新增本地化 key，除非实现时发现现有 key 不可复用。

## 验证

实现阶段需要补充并运行以下验证：

- 更新 `scripts/check_efc_controller_flows.sh`：
  - 断言 EFC Monitor 存在 Visitor 专用判断。
  - 断言 3 个 Mock action 都先走 Visitor guard。
  - 断言真实 EFC Visitor 菜单只保留 Information 分支。
  - 断言虚拟 EFC Visitor 菜单不展示 Edit / Delete。
  - 断言 `Insufficient permissions` 本地化 key 仍存在于 English 和简体中文。
- 运行 `scripts/check_efc_controller_flows.sh`。
- 运行 `scripts/check_efc_i18n.sh`。
- 运行 `git diff --check`。
- 最终实现后按项目规则运行 iPhoneOS build：
  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 风险和边界

- 如果后续产品希望 Visitor 禁止更多 EFC 控制入口，应单独扩展权限规则，避免把本轮 Mock Button guard 泛化到所有 EFC control。
- 虚拟 EFC Visitor 点击右上角菜单时“没有选项”设计为不弹菜单；如果需要可视反馈，应另行确认是否显示权限 Toast。
- 现有 `Status & Settings` 的 header action 代码虽然存在，但当前 UI 不允许点击，不纳入本轮权限改动。
