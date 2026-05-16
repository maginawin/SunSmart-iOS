# Space Debug 功能设计

## 背景

App 需要在进入 Site / Space 后提供一个 Space 级 Debug 入口，用于断开当前 Space 自动 Mesh 连接、扫描当前 Space 内真实 Mesh 节点、查看节点可连接状态和 RSSI，并允许用户直连某个节点进入 Debug 详情页。

当前工程相关上下文：

- Space 右上角菜单由 `SpaceViewController.moreClick()` 动态组装。
- Space 权限由 `SpaceData.spaceOperates` 和 `deviceOperates` 控制。
- Main 页面设备分类由 `DevicesViewController` 拆成 `Lights`、`Switches`、`Sensors`、`Others`。
- SDK 已提供 Mesh Proxy 扫描/RSSI 刷新能力，以及指定节点连接能力。
- 未来 Debug 详情页需要扩展到 BLE 其他 Service，例如 Nordic UART / serial log，不只局限于 SIG Mesh。

## 已确认范围

第一版包含：

- Space 菜单新增 `Debug` 入口。
- Debug 首页扫描当前 Space 内真实 Mesh Node。
- 按 `Lights`、`Switches`、`Sensors`、`Others` 分类展示。
- 搜索到节点后展示并更新 RSSI，未搜索到节点置灰不可点。
- 扫描持续进行，直到用户点击 `Stop`、选择设备或退出 Debug flow。
- 点击可连接节点后停止扫描并连接指定节点。
- 连接成功后进入 Debug 专用详情页。
- 连接失败、连接意外断开、重连和退出恢复逻辑。
- 为未来 Nordic UART / serial log 能力预留 BLE Service 扩展边界。

第一版不包含：

- 不展示 EnOcean Switch、预创建开关、未绑定消防控制器等业务虚拟设备。
- 不实现 Mesh 消息/参数读写工具。
- 不实现 Nordic UART / serial log 的 service discovery、订阅、读写命令。
- 不主动重构现有设备控制页或复用现有设备详情页。

## 入口与权限

Space 右上角菜单新增 `Debug`，菜单顺序为：

`Edit`、`Delete`、`Share`、`Debug`

显示规则：

- 所有构建都可以包含 `Debug` 入口。
- 仅 owner/editor 显示 `Debug`。
- visitor 不显示 `Debug`。
- 现有 `Unbind` 继续按原权限逻辑显示，不被 `Debug` 替代。

点击 `Debug` 后进入新的 Debug flow。进入前关闭菜单，并由 Debug flow 接管 BLE/Mesh 连接生命周期。

## Debug 扫描首页

数据源只使用 `MeshNetworkManager.instance.realNodes`。

页面结构：

- 标题：`Debug`
- 右上角按钮：扫描中显示 `Stop`，停止后显示 `Scan`
- 顶部摘要：展示当前状态与 `Found / Total`
- 列表分组：`Lights`、`Switches`、`Sensors`、`Others`
- Cell 内容：`Group Name - Device Name`、RSSI、连接状态
- 已扫描到节点：正常样式，可点击
- 未扫描到节点：灰色禁用样式，不可点击

扫描行为：

- 进入页面后自动断开当前 Space 自动 Mesh 连接并开始扫描。
- 持续扫描当前 Space 的 Mesh Proxy 广播，直到用户主动停止、选择节点或退出 Debug flow。
- 搜索到节点后，按扫描结果中的 MAC / old MAC 映射回 `Node`。
- 无法映射到当前 Space `realNodes` 的广播不进入 UI。
- RSSI 更新需要 UI 节流，建议 1-2 秒批量刷新一次，避免高频广播导致列表频繁 reload。

分组规则：

- `Node.DeviceType.light` 进入 `Lights`。
- `Node.DeviceType.switches` 进入 `Switches`。
- `Node.DeviceType.sensor` 进入 `Sensors`。
- 其他真实节点类型进入 `Others`，包括 gateway、dongle、emergencyController、unknown 等。

## 连接与详情页

用户点击可连接设备后：

1. Debug 首页停止扫描。
2. 选中设备进入 `Connecting` 状态。
3. 通过 A+ 路线连接指定节点。
4. 连接成功后进入 Debug 专用详情页。
5. 连接失败后回到 Debug 首页的可恢复状态。

Debug 详情页第一版只展示诊断信息：

- 标题：`Group Name - Device Name`
- 连接状态：`Connected`、`Disconnected`、`Connecting`、`Reconnecting`
- Node address
- MAC
- RSSI
- PID / CID
- Device type
- 是否可作为 Proxy
- BLE Services 预留区，用于后续 Nordic UART / serial log

详情页不复用现有设备控制页，避免控制业务、Mesh 自动连接和 Debug 直连会话相互耦合。

## A+ 技术边界

A+ 的目标是第一版尽量复用 SDK 现有扫描/连接能力，同时不堵死未来 BLE 其他 Service 的扩展。

第一版策略：

- 扫描仍使用 SDK 已有 Mesh Proxy 扫描和 Network Key 过滤能力。
- Debug 首页保存每个 found node 最近一次扫描到的 `CBPeripheral` 和 RSSI。
- 连接时优先复用扫描得到的 `CBPeripheral`。
- 如果当前公开 API 无法把 `CBPeripheral` 带入指定节点连接，第一版先使用 `connectProxy(node:)`。
- 代码结构保留 `DebugBluetoothSession` 这一层，让页面只依赖 Debug 会话接口，不直接依赖底层 SDK 细节。

未来 Nordic UART / serial log 扩展原则：

- 不建议 Debug 页面直接抢同一个 `CBPeripheral.delegate`。
- 优先在 SDK 或 Debug 连接层增加小型桥接接口，让 Mesh Proxy bearer 与 UART service 发现/通知共存。
- UART 能力作为 Debug 详情页的独立能力模块追加，不改变扫描首页的数据源和连接生命周期。

## 生命周期与恢复

进入 Debug flow：

- 关闭当前 Space 自动 Mesh 连接。
- 初始化 Debug 会话。
- Debug 首页开始扫描。

Debug 首页进入详情页：

- 停止扫描。
- 保持 Debug flow 的连接接管状态。
- 不恢复 Space 自动 Mesh 连接。

离开整个 Debug flow 回到 Space：

- 停止扫描。
- 取消正在进行的连接尝试。
- 断开当前 Debug 连接。
- 重新走 Space 自动 Mesh 连接流程。

恢复失败不阻塞返回。Space 页现有连接 HUD、KVO 和自动连接逻辑继续负责后续状态展示。

## 错误处理

蓝牙关闭：

- 进入 Debug 或扫描中遇到蓝牙关闭，停止扫描。
- 展示现有 Bluetooth Required 逻辑或等价提示。

无真实节点：

- 展示空状态。
- 不启动无意义扫描。

找不到任何节点：

- 所有 Cell 保持灰色禁用。
- 摘要显示 `0 / Total found`。
- 扫描继续，直到用户点击 `Stop`。

首次连接失败：

- 弹窗提示连接失败。
- 按钮为 `OK` 和 `Scan`。
- `OK`：关闭弹窗，停留在 Debug 首页，设备回到 found 或 idle 状态。
- `Scan`：关闭弹窗，重置列表状态，重新扫描当前 Space 内节点。

详情页连接意外断开：

- 弹窗提示连接已断开。
- 按钮为 `Close` 和 `Re-connect`。
- `Close`：关闭详情页，回到上级 Debug flow。
- `Re-connect`：重新连接当前设备，并展示 `Reconnecting`。

重连失败：

- 弹窗提示连接失败。
- 按钮为 `Close` 和 `Re-connect`。
- `Close`：关闭详情页，回到上级 Debug flow。
- `Re-connect`：再次尝试连接。

连接中返回：

- 取消当前连接尝试。
- 释放 Debug session。
- 如果离开整个 Debug flow，则恢复 Space 自动 Mesh 连接。

## 建议组件边界

`SpaceViewController`

- 只负责在菜单中增加 `Debug` 入口和路由。
- 不承载扫描、连接或 Debug 状态。

`SpaceDebugViewController`

- Debug 首页。
- 负责列表展示、用户操作和 UI 状态绑定。
- 依赖 Debug session / view model，不直接写 CoreBluetooth 细节。

`SpaceDebugDeviceViewController`

- Debug 详情页。
- 展示连接状态和设备诊断信息。
- 预留 BLE Services 区域。

`SpaceDebugViewModel`

- 生成分组列表。
- 维护 found / total、扫描状态、连接状态。
- 负责 UI 刷新节流。

`DebugBluetoothSession`

- 封装进入/退出 Debug flow 的连接接管。
- 封装扫描、停止扫描、连接、断开、重连。
- 保存 node 与 peripheral 的映射。
- 为后续 Nordic UART / serial log 扩展保留接口边界。

## 验证范围

功能验证：

- owner/editor 能看到 `Debug` 菜单项。
- visitor 看不到 `Debug` 菜单项。
- Debug 首页只展示真实 Mesh Node。
- 列表按 `Lights`、`Switches`、`Sensors`、`Others` 分类。
- 扫描中 RSSI 能更新。
- 未 found 节点置灰不可点。
- `Stop` 能停止扫描。
- `Scan` 能重新开始扫描。
- 点击 found 节点后停止扫描并进入连接状态。
- 连接成功进入 Debug 详情页。
- Debug 详情页标题为 `Group Name - Device Name`。
- 首次连接失败弹窗 `OK` / `Scan` 行为正确。
- 详情页意外断开弹窗 `Close` / `Re-connect` 行为正确。
- 退出整个 Debug flow 后释放 Debug 连接并恢复 Space 自动 Mesh 连接。

编译验证：

- 至少验证 `SunSmart` target。
- 因入口和 Debug flow 位于共享代码，修改公共 API、资源、本地化或 target 配置时，同步检查 `Archipelago`、`SLG Sync Plus`、`SylSmart` 是否受影响。

## 实施约束

- 第一版优先复用现有本地化 key。若缺少 `Debug`、`Connected`、`Disconnected`、`Connecting`、`Reconnecting`、`Not Found` 等展示文案，则新增本地化 key，并同步检查相关品牌 target。
- 第一版默认先使用现有 SDK 公开 API 完成扫描与指定节点连接。只有当实现阶段确认无法满足“使用扫描得到的 `CBPeripheral` 连接指定节点”时，才做最小 SDK 扩展。
- Debug 详情页第一版展示 BLE Services 预留区，但以空状态呈现，不提供可点击操作。
