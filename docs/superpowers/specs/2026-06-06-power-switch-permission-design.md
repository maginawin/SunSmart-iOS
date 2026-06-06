# Battery/AC Power Switch 权限优化设计

## 背景

Battery power switch 与 AC power switch 需要补齐 visitor 以及临时受限 editor/owner 的权限限制。当前 App 已有空间内多编辑用户互斥机制：`SpaceViewController` 检查 active members 后，会对后进入 space 的 owner/editor 设置 `space.disableEditorPermission = true`，并通过 `SpaceData.deviceOperates`、`SpaceData.groupOperates` 等权限集合移除编辑能力。

本设计直接复用这套机制，不新增云端权限字段，不修改真实 `SpaceData.permission`。在 power switch 相关页面中，将真实 visitor 与 `disableEditorPermission == true` 的 owner/editor 统一视为只读 visitor。

## 目标

- Editor 保持现有全部权限。
- Owner 保持现有全部权限。
- Visitor 只能查看，不允许修改 battery/ac power switch 状态或配置。
- 当 owner/editor 因后进入 space 被临时限制时，battery/ac power switch 页面完全按 visitor 处理。
- 权限不足时统一提示 `No permission!`。

## 非目标

- 不改变云端权限模型。
- 不新增 Auth 信息。
- 不重构无关的 switch、group、space 权限模块。
- 不修改 kinetic switch 的既有业务行为，只借鉴其权限限制方式。

## 现有机制

`SpaceViewController` 已有以下流程：

- 进入 space 后，若当前用户拥有 owner/editor 编辑权限，会请求 active members。
- 如果发现其他 owner/editor 已在同一 space 内，后进入 App 会触发权限转移提示。
- 用户确认后设置 `space.disableEditorPermission = true`。
- `SpaceData.deviceOperates`、`groupOperates` 等会在 `disableEditorPermission` 为 true 时移除 edit/delete/add 权限，仅保留有限控制能力。

本次实现应借鉴并复用这些权限集合，而不是重新判断 active members。

## 设备详情页设计

目标页面：`PJEightKeySwitchMonitorVC`，覆盖 battery power switch 与 AC power switch 设备页。

有效只读权限判断：

- `space.permission == .visitor`。
- 或 `space.disableEditorPermission == true`。
- 或当前页面依赖的操作权限集合不包含编辑权限。

右上角选项菜单：

- 可编辑用户保持现有菜单逻辑：Edit、Delete、Information、Identify 仍按现有条件展示。
- 只读用户只展示 Information。
- 如果是虚拟 power switch，没有真实设备节点可进入 Information，则点击右上角不展示菜单，也不提示。
- 只读用户不展示 Identify，因为 Identify 属于设备操作。

底部 enable/disable：

- 可编辑用户保持当前 TX enable 更新逻辑。
- 只读用户点击后不改变本地状态、不发 Mesh 消息、不进入 sync，只显示 `No permission!`。
- 如果 UISwitch 视觉状态已被触发，应立即恢复到原状态。

Battery Refresh 与 Identify：

- 只读用户不展示 refresh 按钮。
- 只读用户不展示 Identify 菜单项。
- 可编辑用户保持现有逻辑。

## Group Power Switch 列表设计

目标页面：从 group 页面右上角进入 Switch 类型选择后，选择 Battery power switch 或 AC power switch 展示的 `GroupPowerSwitchesViewController`。

入口权限：

- 继续由 `GroupViewController` 传入 `editable = space.groupOperates.contains(.edit)`。
- 因为 `groupOperates` 已受 `permission`、`disableEditorPermission` 与 OTA 状态影响，visitor 和临时受限 owner/editor 会自然进入只读模式。

只读模式允许：

- 展示 battery/ac power switch 列表。
- 展开或收起每个 switch，用于查看已有配置。

只读模式禁止：

- 切换 enable/disable 状态。
- 点击 Panel 行。
- 点击 Group 行。
- 点击 More Settings 行。
- 点击删除按钮。
- 点击保存按钮。

禁止行为统一显示 `No permission!`。被禁止的行为不得修改本地数据、不得发 Mesh 消息、不得 push 编辑/选择/sync 页面。

Scene 行不在本次用户明确列出的限制项中；为保持与 Panel、Group、More Settings 的编辑属性一致，若 scene 行存在，也应按只读禁止点击并提示 `No permission!`。

## 文案

权限不足提示使用固定展示效果：

- 文案：`No permission!`
- 形式：沿用现有 `XWHUDManager.showTipHUD` toast。

设备详情页用户前一条需求提到 `No permission`，后续补充明确要求注意提示是 `No permission!`，因此本设计统一采用带感叹号版本。

## 数据流

设备详情页：

1. 用户进入 `PJEightKeySwitchMonitorVC`。
2. ViewModel 根据当前 `SpaceData` 得出有效只读状态。
3. UI 根据有效只读状态展示菜单、refresh、enable/disable 交互。
4. 只读用户触发被禁止行为时只显示 toast，不调用持久化、Mesh send、sync flow。

Group Power Switch 列表：

1. `GroupViewController` 根据 `space.groupOperates.contains(.edit)` 创建 `GroupPowerSwitchesViewController`。
2. `GroupPowerSwitchesViewController` 使用 `editable` 控制添加、行编辑、保存、删除与 enable/disable。
3. 只读用户触发被禁止行为时显示 `No permission!` 并阻止后续动作。

## 错误处理

- 权限不足优先于业务校验和 Mesh 操作。
- 权限不足不展示失败弹窗、不触发删除确认、不进入 sync。
- Mesh 操作失败、持久化失败等现有错误处理保持不变。
- 虚拟 power switch 在只读设备详情页右上角无 Information 可展示时，点击菜单按钮无动作。

## 测试计划

- Visitor 进入真实 battery/ac power switch 设备详情页，右上角菜单只展示 Information。
- Visitor 进入虚拟 battery/ac power switch 设备详情页，点击右上角不展示菜单。
- Visitor 点击设备详情页底部 enable/disable，状态不改变并提示 `No permission!`。
- `disableEditorPermission == true` 的 owner/editor 在设备详情页表现与 visitor 一致。
- 可编辑 owner/editor 在设备详情页仍可 Edit、Delete、Information、Identify 和切换 enable/disable。
- Visitor 或临时受限用户从 group 页面进入 battery/ac power switch 列表后，可展开查看。
- 只读用户在 group power switch 列表中点击 enable/disable、Panel、Group、Scene、More Settings、删除、保存时均提示 `No permission!`，且不进入后续页面。
- 可编辑 owner/editor 在 group power switch 列表中保持现有编辑、保存、删除、enable/disable 行为。
- iOS 构建使用项目推荐的 `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` 验证。
