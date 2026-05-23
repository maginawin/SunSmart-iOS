# Battery Power Switch Profile 功能设计

## 背景

当前 App 已在 `devices_config.json` 增加 PID `0x2A01` 和 `0x2A02` 的 Battery Power Switch，并新增图标 `device_battery_power_switch`。这两类设备需要作为 Switch 类设备展示在 Site / Space 页和主页 Switch 分类中；直接添加扫描到设备时，也需要展示在添加设备页的 Switch 分类下。

协议资料只读参考：

- `protocols/0x2A01.json`
- `protocols/0x2A02.json`
- `protocols/2422K8N_US_4DIM.md`

这两个设备都是 Low Power 设备，只能在直接 Add 和 BLE Direct OTA 时允许 App 连接。Add 成功后、OTA 成功后，App 都必须主动断开与设备的 BLE 连接。后续自动 Proxy 连接必须过滤 Low Power enabled 的设备。

## 当前实现结论

SDK 侧已经支持 Battery Power Switch 相关能力，不应重复增加 SDK 接口。已存在能力包括：

- Battery Power Switch key config / reset defaults / LED enabled 的 vendor message 支持。
- Battery Power Switch trigger / action type / key configuration 模型。
- Battery Power Switch required models 与 app key bind 支持。
- Low Power 设备自动 Proxy 连接过滤逻辑。
- 通过普通 Proxy 节点发送 Mesh 配置命令的基础能力。

App 侧当前已经有 8-key switch UI 与本地数据结构：

- Switch 分类页：空状态、数量 `x/16`、添加、编辑、删除、长按编辑、点击进入详情。
- 8-key switch 卡片：`PJEightKeySwitchesViewCell`。
- 8-key switch 详情页：状态 header、8 键面板、刷新弹窗、启用开关、组绑定状态、更多菜单。
- 8-key switch 编辑页：名称、启用状态、面板类型、绑定设备、选择组、选择场景、更多设置、删除、保存、未保存退出提示。
- `PJEightKeySwitchRepository` 目前保存 panel type 与 more settings。
- `DeviceSwitchData.linkGroupAddress` 可复用为 Battery Power Switch 的内部虚拟组地址。

当前缺口：

- 直接添加 BPS 后没有确保分配内部虚拟组。
- Edit 保存只保存本地 UI 配置，没有下发 BPS 的 `0x4C` key config。
- 现有 `needSyncData` 不能表示 BPS 的 `0x4C` 配置是否已同步。
- BPS 同步失败后缺少专属 sync state / hash 记录。

## 范围

本阶段只实现直接添加的 Battery Power Switch，不实现虚拟设备。

本阶段覆盖：

- `0x2A01` 默认 Scene Profile。
- `0x2A02` 默认 Brightness Profile。
- Edit 页切换 Profile 并保存。
- BPS 内部虚拟组分配和保存。
- BPS key config 下发。
- target groups 的 capability models 订阅 BPS 虚拟组。
- 同步失败 UI 与重新同步。

暂不覆盖：

- 虚拟 Battery Power Switch。
- 自动后台静默重试。
- 删除设备后的独立删除同步失败 UI。

## 数据模型

BPS 继续复用 `DeviceSwitchData` 保存用户期望配置：

- 名称。
- 启用状态。
- `linkGroupAddress`。
- 绑定 groups。
- 待解绑 groups。
- Scene A/B/C/D。
- proxy node address。

BPS 专属 metadata 继续由 `PJEightKeySwitchRepository` 管理，并增加同步元数据：

- `syncState`：`synced` / `pending` / `failed`。
- `desiredConfigVersion`：每次 Edit 保存成功递增。
- `desiredConfigHash`：根据当前 desired config 生成。
- `appliedConfigHash`：最后一次完整同步成功的 hash。
- `lastSyncFailedReason`：最后失败原因。
- `lastSyncedAt`：最后同步成功时间。

`desiredConfigHash` 至少包含：

- Profile 类型。
- 启用状态。
- Scene A/B/C/D。
- target groups。
- more settings。
- `linkGroupAddress`。
- 生成 key config 所需的 app key index。

状态判断：

- `syncState == synced` 且 `desiredConfigHash == appliedConfigHash`：正常。
- `syncState == pending`：需要同步。
- `syncState == failed`：同步异常。
- `desiredConfigHash != appliedConfigHash`：需要同步。

现有 `DeviceSwitchData.needSyncData` 不能单独承担 BPS 同步判断。`PJEightKeySwitchData.displayStatus` 需要合并 BPS 专属 sync state / hash，作为 `syncIssueBoundSwitch` 的来源之一。

## 内部虚拟组

BPS 只分配一个内部虚拟组地址，使用 `DeviceSwitchData.linkGroupAddress`。

规则：

- 直接添加 BPS 到 space 后，如果没有 `linkGroupAddress`，需要分配并保存。
- Edit 保存前如果仍没有 `linkGroupAddress`，需要先分配。
- 不使用 `subLinkGroupAddress`。
- 虚拟组不回收；删除 BPS 后继续保留在数据库中。
- target groups 中的目标设备通过订阅这个 `linkGroupAddress` 来响应 BPS 按键命令。

## Edit 保存流程

Edit 页保存代表“用户期望配置已保存”，不代表设备端配置已同步成功。

保存流程：

1. 用户点击 Save。
2. 构建新的 desired config。
3. 确保存在 `linkGroupAddress`。
4. 保存名称、启用状态、Profile、Scene、target groups、more settings。
5. 生成新的 `desiredConfigHash`。
6. 递增 `desiredConfigVersion`。
7. 标记 `syncState = pending`。
8. 保存数据库。
9. 返回详情页，标题立即更新为最新 switch name。
10. 进入或提示进入 BPS 同步流程。

如果同步失败，不回滚数据库。UI 继续展示 desired config，同时显示 sync issue。

## Profile 映射

默认 Profile：

- PID `0x2A01`：Scene Profile。
- PID `0x2A02`：Brightness Profile。

用户可在 Edit 页切换 Profile，保存后写入 desired config；同步成功后设备端生效。

所有 key config 使用当前 space 的 app key，目标地址统一使用 `linkGroupAddress`。

### Scene Profile

- Button 0：click recall Scene 1；未选择 scene 则不下发。
- Button 1：click recall Scene 2；未选择 scene 则不下发。
- Button 2：click recall Scene 3；未选择 scene 则不下发。
- Button 3：click recall Scene 4；未选择 scene 则不下发。
- Button 4：click brightness step up；press 持续调亮；press release 停止。
- Button 5：click brightness step down；press 持续调暗；press release 停止。
- Button 6：click ON；press AUTO；press release 不下发。
- Button 7：click OFF。

### Brightness Profile

- Button 0：click lightness 100%。
- Button 1：click lightness 75%。
- Button 2：click lightness 50%。
- Button 3：click lightness 25%。
- Button 4：click brightness step up；press 持续调亮；press release 停止。
- Button 5：click brightness step down；press 持续调暗；press release 停止。
- Button 6：click ON；press AUTO；press release 不下发。
- Button 7：click OFF。

### 命令语义

- ON：Generic OnOff Set，value 为 on。
- OFF：Generic OnOff Set，value 为 off。
- AUTO：Light LC OnOff Set，value 为 on。
- 短按 Step：Generic Level Delta，约 20%，即 `±13107`。
- 长按持续调光：Generic Level Move，约 5 秒完成 `0...65535` 渐变，即 `±13107`。
- 长按松开停止：Generic Level Move，value 为 `0`。
- 亮度百分比：按 `UInt16.max * percentage` 换算。

长按相关事件只使用 `press` 和 `press release`，不使用 `long press` / `long release`。

## Target Groups 订阅规则

capability models 指目标设备侧可响应的 Server models，不是 BPS 自身 Client models。

至少包含：

- Generic OnOff Server。
- Generic Level Server。
- Scene Server。
- Light Lightness Server。
- Light LC Server。

订阅规则：

- 对所有 selected target groups 中的设备，只要存在 capability models 中的 model，就在对应 model 下订阅 BPS 的 `linkGroupAddress`。
- 如果某设备不存在对应 model，跳过。
- 允许 target groups 中的设备冗余订阅全部 capability models。
- 切换 Profile 时，如果 target groups 没变，不需要计算新增/删除订阅。
- target groups 被移除时，必须对被移除 groups 的对应 capability models 退订 `linkGroupAddress`，否则旧 group 会继续响应 BPS。

## 同步执行流程

BPS 同步不能直连 BPS，只能通过其它 Proxy 节点发送 Mesh 配置命令。

前置条件：

- 当前 Mesh 网络存在可用 Proxy 节点。
- 可用 Proxy 节点不能是 Low Power enabled 的 BPS。
- 当前 space 有 app key。
- BPS 已绑定当前 space app key 到所有 required modes/models。
- BPS 有 `linkGroupAddress`。

发送顺序：

1. 通过其它 Proxy 节点连接 Mesh。
2. reset BPS 配置。
3. 依次下发 8 个按钮的 click / press / press release 配置。
4. 无功能事件不下发，因为 reset 后默认为空。
5. 对 target groups 的 capability models 订阅 `linkGroupAddress`。
6. 对已移除 target groups 的 capability models 退订 `linkGroupAddress`。
7. 全部成功后标记 `syncState = synced`，并设置 `appliedConfigHash = desiredConfigHash`。

任何一步失败：

- 不重试。
- 不回滚 desired config。
- 标记 `syncState = failed`。
- 记录失败原因。
- 保留待退订信息。
- UI 显示 sync issue。

下一次重新同步时，从 reset BPS 配置开始完整重放 desired config，不从失败步骤续跑。

## UI 行为

Switch 分类列表：

- BPS 计入 Switch 页面 16 个上限。
- BPS 显示在 Switch 分类，不进入 Others。
- 如果 `syncState != synced` 或 `desiredConfigHash != appliedConfigHash`，卡片显示 sync issue 图标。

BPS 详情页：

- 面板显示 desired config。
- 标题显示最新 switch name。
- Header 根据 BPS sync state 显示 normal 或 sync issue。
- sync issue 时提供重新同步入口。

Edit 页：

- 读取和编辑 desired config。
- 若当前存在 sync issue，用户保存后继续按最新 desired config 同步。
- 若用户进入 Edit 后不改动并退出，不改变 sync state。
- 未保存退出提示保持现有行为。

同步失败页：

- 展示失败步骤或失败设备。
- 允许 Retry。
- 用户不 Retry 并退出时，`syncState` 保持 failed。
- 后续从列表或详情页 sync issue 入口继续同步。

## 连接规则

BPS 作为 Low Power 设备，连接规则固定：

- 直接 Add 时允许 App 连接 BPS。
- BLE Direct OTA 时允许 App 连接 BPS。
- Add 成功后主动断开 BPS BLE 连接。
- OTA 成功后主动断开 BPS BLE 连接。
- 自动 Proxy 连接过滤 Low Power enabled 的 BPS。
- Edit 保存、重新同步、target group 订阅都不能直连 BPS。

## 失败处理

保存 desired config 后，如果 BPS 配置过程失败，用户看到的是：

- Edit 修改已保存。
- 详情页标题和面板更新为最新 desired config。
- 设备状态显示 sync issue。
- 真实设备端可能仍是旧配置、空配置或部分配置。
- 用户可通过 sync issue 入口重新同步。

重新同步使用数据库中的 desired config 重新生成完整同步计划，并重新从 reset 开始执行。

不做后台静默自动重试。原因是 BPS 是 Low Power 设备，App 不能直连，只能依赖其它 Proxy 节点；静默失败会导致用户感知不清晰。

## 测试计划

需要覆盖的验证点：

- PID `0x2A01` 添加后默认 Scene Profile。
- PID `0x2A02` 添加后默认 Brightness Profile。
- BPS 直接添加后存在 `linkGroupAddress`。
- BPS 添加后 App 主动断开 BLE。
- 自动 Proxy 连接过滤 Low Power enabled BPS。
- Edit 页修改名称后返回详情页标题更新。
- Edit 页切换 Profile 后 desired config 保存。
- Scene Profile 生成正确 key config。
- Brightness Profile 生成正确 key config。
- OFF 使用 Generic OnOff Set off。
- AUTO 使用 Light LC OnOff Set on。
- 长按调光使用 press / press release，不使用 long press / long release。
- target groups 的 capability models 订阅 `linkGroupAddress`。
- 移除 target groups 后退订 `linkGroupAddress`。
- reset 或 key config 失败后显示 sync issue。
- target group 订阅失败后显示 sync issue。
- sync issue 入口可重新同步，并从 reset 开始重放。
- 同步成功后 `syncState = synced`，`appliedConfigHash = desiredConfigHash`。
- `xcodebuild` 通过项目指定命令编译。

## 自检结论

- 本设计聚焦直接添加的 Battery Power Switch，不包含虚拟设备。
- 失败处理与 Kinetic Switch 的 desired config 模式一致，但增加了 BPS 专属 sync state / hash 来覆盖 `0x4C` 配置差异。
- OFF / AUTO / 调光 / 长按事件均按已确认要求固定。
- 同步流程明确禁止直连 BPS，符合 Low Power 连接限制。
- 无未确认的实现前置问题。
