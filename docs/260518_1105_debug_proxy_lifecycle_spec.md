# Debug Proxy 生命周期调整规格

## 背景

当前 Space Debug flow 在进入调试页时会主动断开 Mesh Proxy，并在退出 Debug flow 时释放调试连接后重新走 Space 自动连接流程。这会导致用户从正常控制进入调试时，原本可用的 Proxy Node 被展示为断开，调试页和正常控制页的 Proxy 通路不一致。

本次目标是让 Site / Space 右上角菜单中的 `Debug` 使用与正常控制相同的 Proxy 连接通路：进入调试页不主动断开当前 Proxy；用户只有在手动点击其它已扫描到的设备行时才切换 Proxy；调试页内 Proxy 自然断开时不自动连接；退出调试页后恢复 Space 的自动连接 Proxy Node 逻辑。

## 范围

本次包含：

- 调整 Debug 进入、扫描、点击设备、返回列表和退出 Debug 的 Proxy 生命周期。
- Debug 列表展示当前已连接 Proxy Node 的 `Connected` 状态。
- 保留调试页扫描周围当前 Space 设备广播并更新 RSSI 的能力。
- 未扫描到且未连接的设备行继续不可点击，不尝试连接。
- 退出整个 Debug 页后恢复 Space 自动连接 Proxy Node 的逻辑。
- 从 Space 右上角菜单进入 Debug 不受编辑权限限制，`visitor` 也可以进入。

本次不包含：

- 不重构正常控制页的自动连接策略。
- 不新增全局 Proxy 会话管理器。
- 不改变 UART 页面功能、过滤、导出等现有行为。
- 不修改品牌资源、target 配置或 Pod 依赖。

## 推荐方案

采用轻量改造现有 Debug 会话的方案，保持影响范围集中在：

- `SpaceDebugViewController`
- `SpaceDebugViewModel`
- `SpaceDebugDeviceCell`
- `DebugBluetoothSession`
- `SpaceViewController.openSpaceDebug()` 的退出回调

`DebugBluetoothSession` 从“进入 Debug 时接管并断开原连接”改为“复用当前 Mesh 连接，并只在用户手动切换时断开旧 Proxy”。调试页内不会触发自动连接 Proxy；退出 Debug 后由 Space 原有自动连接逻辑重新接管。

## 状态模型

`SpaceDebugViewModel` 需要维护当前连接地址，例如 `connectedAddress`。

每个设备行的状态按优先级判断：

1. `Connecting`：用户正在连接该设备。
2. `Connected`：该设备地址等于当前 `currentProxy?.node` 的地址。
3. `Found`：扫描到了该设备的广播、`peripheral` 和 RSSI。
4. `Not Found`：未连接且未扫描到。

可点击规则：

- `Connected` 行可点击，直接进入调试设备页。
- `Found` 且未连接的行可点击，执行手动切换连接。
- `Not Found` 行不可点击，不发起连接尝试。

展示规则：

- 当前 Proxy Node 行显示 `Connected`。
- 当前 Proxy Node 行可以不依赖扫描 RSSI；如已有 RSSI 可保留展示，否则 RSSI 可显示 `--`。
- 没有 Proxy Node 连接时，所有行按扫描结果展示蓝牙信号。
- 未扫描到设备使用置灰样式，保持现有不可点击体验。

## 生命周期

进入 Debug 页：

1. 不主动断开当前 Proxy。
2. 停止已有 RSSI 刷新任务，避免与调试页扫描互相覆盖。
3. 加载 Mesh 扩展数据，初始化当前 Space 的 `realNodes`。
4. 如果当前 `currentProxy?.node` 属于当前 Space，将对应行标记为 `Connected`。
5. 自动开始扫描周围当前 Space 内设备广播，持续更新 RSSI。
6. 扫描期间不为了更新 RSSI 而断开当前 Proxy。

进入权限：

- Debug 菜单不使用 `canEditing` 或设备编辑权限作为入口条件。
- `owner`、`editor`、`visitor` 在当前 Space 状态正常且不需要重新验证密码时都可以看到并进入 Debug。

调试页内 Proxy 自然断开：

- 不自动连接新的 Proxy Node。
- 当前连接行退出 `Connected` 状态。
- 如果在设备页，沿用现有断开提示和手动重连能力。
- 如果在列表页，只更新列表状态，等待用户手动点击已扫描到的设备。

点击设备行：

- 点击已连接 Proxy Node 行：停止扫描，直接进入调试设备页，不重新连接。
- 点击未连接但已扫描到的设备行：停止扫描；如当前存在 Proxy，先断开当前 Proxy；再连接点击行对应设备；成功后更新当前连接地址并进入调试设备页。
- 点击未连接且未扫描到的设备行：无操作，行保持不可点击。

从设备页返回 Debug 列表：

- 不主动断开当前 Proxy。
- 扫描保持停止状态。
- 右上角显示 `Scan`。
- 点击 `Scan` 后继续扫描周围设备并更新 RSSI，不断开当前 Proxy。

退出整个 Debug 页回到 Space：

1. 停止扫描。
2. 停止 UART 消息接收并清理调试缓存。
3. 不为了退出 Debug 主动关闭仍然可用的当前 Proxy。
4. 调用 Space 原有自动连接入口，让正常控制页面恢复自动连接 Proxy Node 的逻辑。
5. 如果当前 Proxy 仍连接，恢复逻辑应尽量复用当前连接；如果已断开，则由 Space 自动连接逻辑选择可用 Proxy。

## 错误处理

蓝牙关闭：

- 维持现有蓝牙状态判断。
- 不能扫描或连接时进入现有 Bluetooth Required 流程或等价提示。
- 不额外断开已有 Proxy 状态。

当前 Proxy 不属于当前 Space：

- Debug 列表不显示 `Connected`。
- 进入 Debug 不主动断开该 Proxy。
- 用户点击当前 Space 内已扫描到的设备时，按手动切换逻辑断开旧 Proxy 并连接目标设备。

当前 Proxy 节点地址缺失：

- 视为没有已连接行。
- 列表按扫描 RSSI 展示。
- 不主动断开当前 Proxy。

连接目标失败：

- 停留在 Debug 列表页。
- 目标行退出 `Connecting`。
- 如果旧 Proxy 已在手动切换过程中断开，不自动恢复旧 Proxy。
- 用户可重新点击 `Scan` 查找设备或点击其它已扫描到的设备。

设备页意外断开：

- 沿用现有断开提示。
- 用户可选择关闭返回 Debug 列表，或手动重连当前设备。
- 自动连接 Proxy Node 仍然只在退出整个 Debug 页后恢复。

## 验证范围

功能验证：

- 进入 Debug 前已有当前 Space Proxy：进入后对应行显示 `Connected`，Proxy 不被主动断开。
- `visitor` 权限的 Space：右上角菜单显示 `Debug`，可进入调试页。
- 进入 Debug 前无 Proxy：所有设备只按扫描结果展示 RSSI，未扫描到不可点。
- 调试页内 Proxy 自然断开：不自动连接新的 Proxy Node。
- 点击已连接行：直接进入设备页，不触发连接重试。
- 点击已扫描到的其它设备：先断开当前 Proxy，再连接目标设备，成功后进入设备页。
- 点击未扫描到的设备：不可点击，不发起连接。
- 从设备页返回 Debug 列表：不主动断开当前 Proxy，右上角 `Scan` 可继续扫描 RSSI。
- 点击 `Scan`：只恢复扫描，不断开当前 Proxy。
- 退出 Debug 回 Space：恢复 Space 自动连接 Proxy Node 的逻辑。

编译验证：

- 至少执行 `SunSmart` target 的 Debug iphoneos 编译。
- 本次预期不修改资源、本地化、target 配置或 Pod 依赖；若实施中触及这些范围，需要同步检查相关品牌 target 影响。

## 实施约束

- 保持改动聚焦，不顺手重构正常控制页或 SDK 自动连接机制。
- 不在调试页内引入自动连接 Proxy 的新路径。
- 不将未扫描到设备改为可点击。
- 不改变 UART 页面现有数据缓存、过滤、清空、导出行为。
