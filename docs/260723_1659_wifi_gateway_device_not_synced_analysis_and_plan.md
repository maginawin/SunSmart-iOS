# WiFi Gateway `Devices not synced` 展示与同步入口分析

## 结论

在当前 `wifi-gateway` worktree 中，预期能力已经存在，不存在“WiFi Gateway 缺少 `Devices not synced` 提示及点击同步入口”的代码缺口。

当同时满足以下条件时，WiFi Gateway 页面会在 `Name` 右侧展示与 AC Power Switch Edit 页面相同视觉语义的提示按钮：

1. `node.isKeybindComplete == true`，页面处于正常详情态；
2. `node.getNodeSyncGatewayData(gateway: gatewayModel)` 非空，即本地期望的 Gateway 配置与 Node 当前状态存在差异。

按钮使用：

- 本地化 Key：`devices_not_synced`
- English：`Devices not synced`
- 简体中文：`设备未同步`
- 图标：`schedule_sync_failed`
- 文字颜色：`Red_Color`

用户需求中写的是单数 `Device not synced`，但 AC Power Switch 当前实际使用的是复数 `Devices not synced`。若目标是“与 AC Power Switch 一样”，应继续复用现有 `devices_not_synced`，不新增单数文案。

## 状态边界

当前设计明确区分两个状态：

| Node 状态 | WiFi Gateway 页面 | 同步入口 |
| --- | --- | --- |
| `isKeybindComplete == false` | Repair 空状态，不展示正常详情 | `REPAIR` |
| `isKeybindComplete == true` 且 Gateway 差异非空 | 正常详情 | Name 右侧 `Devices not synced` |
| `isKeybindComplete == true` 且 Gateway 差异为空 | 正常详情 | 不展示未同步提示 |

因此，如果“需要同步”指的是 Key Bind 尚未完成，Name 区域不展示提示是既有状态优先级，并非组件遗漏。

## 源码证据

### 1. WiFi Gateway 使用共享 Gateway 编辑页结构

- `SiteViewController.gatewayOperationClickAction` 在 `node.isWiFiGateway == true` 时创建 `WiFiGatewayViewController`。
- `WiFiGatewayViewController` 继承 `GatewayViewController`。
- `WiFiGatewayViewController.sections` 只移除 `.info`，保留 `.name`，因此共享 Name section header 的展示与点击处理。

涉及文件：

- `SunSmart/Main/Site/Controller/SiteViewController.swift`
- `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
- `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`

### 2. Name 右侧提示已经实现

`GatewayViewController.tableView(_:viewForHeaderInSection:)` 在 `.name` 分支中：

1. 计算 `node.getNodeSyncGatewayData(gateway: gatewayModel)`；
2. 差异非空时显示 `GatewaySectionHeaderView.operationBtn`；
3. 设置 `schedule_sync_failed` 图标；
4. 设置 `devices_not_synced` 本地化文案；
5. 设置红色文字及图标在左、文字在右的布局。

`GatewaySectionHeaderView.operationBtn` 是可点击的 `UIButton`，不是只读 Label。

### 3. 点击后已进入 WiFi Gateway 专用同步流程

Name header 的点击回调按以下顺序执行：

1. 检查当前是否正在连接；
2. 检查 `canConfigureCurrentGateway` 权限；
3. 调用 `prepareForGatewayRecovery`；
4. WiFi Gateway override 会检查在线状态和当前 WiFi 操作，并在需要时等待自动请求结束；
5. 调用 `resync(trigger: .devicesNotSynced)`；
6. Push `SyncDevicesViewController(type: .gatewayRecovery(...))`；
7. 同步成功后刷新持久化 Server Information、Gateway 数据、保存按钮和 table view。

该流程比普通 `.devices([node])` 更完整，会执行 Gateway Recovery 的初始化、Associated Spaces、Project、Subnet AppKey、WiFi Server Information 和最终差异校验。

### 4. 与 AC Power Switch 的对比

| 能力 | AC Power Switch Edit | WiFi Gateway |
| --- | --- | --- |
| Name 右侧提示 | `syncFailedButton` | `GatewaySectionHeaderView.operationBtn` |
| 显隐真值 | `needsPowerSwitchSyncNotice` | `getNodeSyncGatewayData(...).isEmpty == false` |
| 文案 Key | `devices_not_synced` | `devices_not_synced` |
| 图标 | `schedule_sync_failed` | `schedule_sync_failed` |
| 红色提示 | 是 | 是 |
| 支持点击 | 是 | 是 |
| 点击结果 | Battery Power Switch Sync | Gateway Recovery Sync |

两者不是同一个 UIKit View 类型，因为页面容器不同，但视觉契约和交互契约一致。

## 已完成验证

- 已完整检查上述页面路由、状态计算、UI 配置和点击数据流。
- 已运行 `scripts/check_wifi_gateway_repair_recovery.sh`。
- 结果：`PASS: WiFi Gateway Repair initialization contracts`
- 当前结论属于源码与静态契约验证，未用真实 WiFi Gateway 构造差异状态进行 UI/同步验收。

## 如果真机仍未展示，优先采集的证据

不建议先重复添加第二个按钮。应在同一次复现中确认：

1. `node.isKeybindComplete` 的实际值；
2. `node.getNodeSyncGatewayData(gateway: gatewayModel)` 的数量和具体 `NodeSyncData` 类型；
3. 页面是否进入正常详情态，还是 Repair 空状态；
4. Name section header 创建时 `operationBtn.isHidden` 的最终值；
5. 差异是在进入页面前已存在，还是页面停留期间才由 Mesh Status 更新产生。

若差异非空但按钮仍隐藏，才可确认存在运行时刷新问题；若差异为空，则问题在“需要同步”的状态来源或持久化数据，而不在 UI 组件。

## 可选方案

### 方案 A：保持生产代码现状，仅补回归保护（推荐）

- 不修改现有 UI、状态真值和同步入口。
- 增加聚焦契约测试，固定以下约束：
  - WiFi Gateway 保留 Name section；
  - Gateway 差异非空时使用 `devices_not_synced` 和 `schedule_sync_failed`；
  - 点击必须经过 `prepareForGatewayRecovery`；
  - 最终进入 `.gatewayRecovery(..., trigger: .devicesNotSynced)`；
  - 同步成功或返回页面后重新计算显隐。
- 补充真机验收：制造 Project、Associated Spaces、Subnet AppKey 或 Server Information 差异，确认提示出现、可点击、完成后消失。

优点：最聚焦，不重复实现已有功能，也不改变 4G Gateway、AC Power Switch 或多品牌 target 的行为。

### 方案 B：针对页面停留期间的状态变化增加即时刷新

仅在能复现“进入页面后才产生 Gateway 差异，提示没有即时出现”时采用：

- 在 Gateway 同步相关 Node 数据更新时间变化后，仅刷新 `.name` section；
- 重新计算 Gateway 差异并更新提示；
- 增加差异由空变非空、由非空变空的刷新测试。

该方案解决的是动态刷新时机，不是组件缺失。当前没有证据证明必须修改。

### 方案 C：抽取 AC Power Switch 与 Gateway 共用 View 组件

- 把图标、文案和按钮样式抽为共享 `DeviceNotSyncedButton`；
- AC Power Switch 和 Gateway 分别接入。

不推荐。两页布局容器不同，现有视觉与行为已经一致；抽取会扩大改动和多 target 验证范围，但不能解决状态真值或刷新问题。

## 推荐确认项

建议确认采用方案 A：不改生产代码，只补回归契约和真机验收清单。

如果已有真机复现，请先提供或采集上述五项状态证据，再决定是否进入方案 B。不要按“组件缺失”重复实现按钮。
