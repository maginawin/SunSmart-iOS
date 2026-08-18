# Gateway 时区自动同步提示需求分析与开发方案

## 结论

需求的主流程已经明确：进入 Gateway 页面、目标 Gateway 蓝牙 Mesh Proxy Ready、完成时区检查后，如果需要同步，同时展示 `Sync required` 并自动弹出 `Gateway time zone needs sync`；`Later` 关闭，`SYNC NOW` 复用现有同步流程。

但需求还缺少几个会直接影响重复弹窗和异常场景的边界定义。建议按本文“推荐口径”补齐后实施，不新增业务文案，不改变现有手动同步语义。

## 当前实现链路

1. `GatewayViewController` 是 4G Gateway 页面基类，`WiFiGatewayViewController` 继承它，因此 Time Zone、Clock、蓝牙 Proxy Ready、TimeGet 和 TimeSet 流程由两类 Gateway 共用。
2. 页面可见时会尝试连接当前目标 Gateway；只有 `currentProxyReadyContext` 的 Node Address 与当前 Gateway 一致，才进入 Proxy Ready。
3. 每个 Proxy Ready Session 首次成功后，`gatewayProxyDidBecomeReady` 只自动执行一次 `readGatewayClock()`。
4. `readGatewayClock()` 完成后更新 `GatewayDetailClockState`：
   - Gateway Offset 与目标 Site Offset 不一致：`requiresSync = true`；
   - 目标 Offset 无法 Mesh 编码：`requiresSync = true`；
   - TimeGet/校验失败、Gateway 时区未知：现有语义同样设为 `requiresSync = true`；
   - Offset 一致：`requiresSync = false`。
5. Time Zone Section Header 根据 `requiresSync` 展示或隐藏 `Sync required`。
6. 当前只有用户点击 `Sync required` 时才调用 `showGatewayClockSyncPrompt()`；自动 TimeGet 完成后不会自动弹窗。
7. 弹窗已经具备目标行为：
   - `Later` 是取消操作，直接关闭弹窗；
   - `SYNC NOW` 在弹窗关闭动画完成后调用 `synchronizeGatewayClock()`；
   - 同步流程执行 Model Binding、TimeSet、最终 TimeGet 回读校验、本地保存和 Gateway Cloud 更新排队。

## 需求完整性分析

### 已明确

- 触发前提：进入 Gateway 页面并且目标 Gateway 蓝牙连接成功。
- 展示条件：检查结果判定 Gateway 时区需要同步。
- 展现形式：保留 `Sync required`，同时自动展示现有同步弹窗。
- 用户动作：`Later` 关闭；`SYNC NOW` 复用现有同步流程。

### 尚未明确的边界及推荐口径

#### 1. Gateway 类型范围

推荐：同时覆盖 Wi-Fi 与 4G Gateway。

原因：两者已共享 `GatewayViewController` 的时区检查和同步实现，只对其中一个类型生效会造成同一功能行为不一致，也需要额外的类型分支。

#### 2. “需要更新”的判定范围

推荐：完全复用现有 `gatewayClockState.requiresSync`，不另建第二套判定。

因此以下情况都显示 `Sync required` 并自动提示：

- Gateway Offset 与目标 Site Offset 不一致；
- Gateway 时间/时区读取失败或未知；
- 目标 Offset 无法 Mesh 编码。

这与当前手动提示保持一致。若产品只希望“已成功读取且明确不一致”时自动弹窗，需要额外将“未知/读取失败”排除；该选择会导致页面仍显示 `Sync required`，但不会自动弹窗。

#### 3. 自动弹窗频率

推荐：每个目标 Gateway 的 Proxy Ready Session 最多自动弹出一次。

- 首次检查后需要同步：自动弹一次；
- 选择 `Later`：本 Session 不再自动弹，但 `Sync required` 保留，用户仍可手动点击；
- 返回子页面后仍是同一 Proxy Ready Session：不重复弹；
- 蓝牙断开并重新建立新的 Proxy Ready Session：重新检查，仍需要同步时可再次自动弹；
- 同步失败：保留 `Sync required`，本 Session 不再次自动打扰，用户手动重试。

该口径可避免页面刷新、重复 Proxy Ready 通知、系统时间通知或失败回调造成连续弹窗。

#### 4. 与其他弹窗冲突

推荐：自动提示不得关闭或覆盖当前已经显示的 `SRAlertView`。

现有 `SRAlertView.show()` 会先关闭已有弹窗；如果直接在异步 TimeGet 回调中调用，可能把用户正在操作的其他弹窗替换掉。自动提示应在以下条件同时满足时展示：

- Gateway 页面仍可见；
- 当前仍是同一个目标 Gateway、同一个 Proxy Ready Session；
- `requiresSync == true`；
- 当前不在同步中，也没有等待启动的同步；
- 当前没有其他 `SRAlertView`。

若其他弹窗占用展示层，则保留本次待提示状态，在页面仍可见且弹窗空闲后再展示；页面退出或 Session 失效时取消待提示。

#### 5. 检查期间用户主动同步

推荐：如果用户已通过 `Sync clock` 或 `Sync required` 主动发起同步，取消本 Session 的待自动提示，避免读回调完成后再弹一次。

现有 `pendingGatewayClockSync` 已支持“初始 TimeGet 未完成时用户先点同步”，本次只需让自动提示状态与该流程互斥，不改同步实现。

#### 6. 页面不可见与连接失效

推荐：异步检查完成时页面不可见，不在其他页面上弹出 Gateway 提示；回到同一个 Gateway 页面且 Session 仍有效时再尝试展示。连接已断开或切到其他 Proxy 时，丢弃该 Session 的待提示。

## 推荐开发方案

### 1. 增加 Session 级自动提示状态

在 `GatewayViewController` 的 Gateway Clock 状态旁增加聚焦的自动提示状态，至少记录：

- 已完成自动提示的 Proxy Ready Session ID；
- 当前待展示的 Proxy Ready Session ID；
- 延迟尝试展示的可取消任务。

不把“是否已提示”写入数据库或 UserDefaults；它属于页面连接 Session 的临时 UI 状态。

### 2. 从首次 TimeGet 完成点触发判定

为 `readGatewayClock()` 区分“Proxy Ready 后的首次检查”和“系统时间变化后的普通重读”。仅首次检查完成后请求自动提示。

顺序保持为：

1. 接收 TimeGet 结果；
2. 更新 `gatewayClockState`；
3. Reload Time Zone/Clock，使 `Sync required` 先进入页面状态；
4. 若没有用户主动同步等待项，再请求自动展示弹窗。

这样自动弹窗与 Header 使用同一个 `requiresSync` 快照，不会出现提示已弹但 Header 未更新的短暂不一致。

### 3. 收口手动与自动弹窗入口

保留现有弹窗文案和 `showGatewayClockSyncPrompt()` 的同步动作，但在上层增加手动/自动两种触发入口：

- 手动触发：用户点击 `Sync required`，取消待自动提示并立即按现有行为展示；
- 自动触发：通过页面可见性、Session、同步状态和弹窗占用检查后展示。

`Later` 不改变 `gatewayClockState`；`SYNC NOW` 继续调用现有 `synchronizeGatewayClock()`，不复制 TimeSet 流程。

### 4. 生命周期清理

- Proxy 断开或切换 Session：清除待自动提示和延迟任务；
- 页面离开：取消延迟展示，防止跨页面弹窗；
- 页面重新可见：若同一有效 Session 仍有待提示，再尝试展示；
- 用户主动同步：将本 Session 标记为已处理，阻止自动重复弹窗。

### 5. 测试与契约

优先补充可独立验证的提示状态测试，覆盖：

1. Offset 一致时不自动弹；
2. Offset 不一致时 Header 与自动弹窗条件同时成立；
3. 读取失败/未知时按推荐口径自动弹；
4. 同一 Session 最多自动弹一次；
5. `Later` 后同一 Session 不重复弹，Header 仍保持 `Sync required`；
6. 新 Session 可重新检查并自动弹；
7. 页面不可见、Session 不匹配、已有其他 Alert、正在同步时不立即弹；
8. Alert 空闲且 Session 仍有效时补弹；
9. 用户主动同步会取消待自动提示；
10. Wi-Fi 子类继续调用共享的 Proxy Ready 实现。

同时更新 Gateway Detail Runtime Contract，约束自动提示必须从首次 TimeGet 完成链触发、不得绕过现有 `requiresSync` 和 `synchronizeGatewayClock()`。

## 验证计划

### 自动化检查

- 运行 Gateway Clock 纯逻辑测试和 Runtime/UI Contract；
- 运行 Gateway Information、Fast Add、Wi-Fi Proxy Ready 相关回归检查；
- 校验中英文 `Localizable.strings` 和 `project.pbxproj`；
- 运行 `git diff --check`；
- 对 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 执行 generic iPhoneOS、Debug、关闭签名构建，不使用 Simulator。

当前基线注意项：`scripts/check_gateway_information_time.sh` 引用的 `SunSmart/Assets.xcassets/Device/Gateway/gateway_clock_sync_loading.imageset/gateway_clock_sync_loading.svg` 当前不存在，脚本会在 Runtime Contract 阶段中止；实际页面已改用 `site_entry_sync_loading`。实施验证时应先核对并聚焦修复该测试资源参数，避免把脚本路径问题误判为本需求回归。

### 真机验收矩阵

- Wi-Fi Gateway、4G Gateway 各验证一次；
- 已同步：连接并检查后不显示 `Sync required`，不弹窗；
- 明确不一致：同时显示 `Sync required` 和弹窗；
- `Later`：只关闭弹窗，Header 保留，点击 Header 可再次打开；
- `SYNC NOW` 成功：沿现有流程同步，最终隐藏 `Sync required` 并显示成功 Toast；
- 同步失败：保留 `Sync required`，显示失败 Toast，可手动重试；
- TimeGet 失败/未知：验证未知文案与推荐自动提示口径；
- 弹窗展示前后断开/重连：无跨页面弹窗，新 Session 可重新提示；
- 页面已有其他 Alert：不被自动提示强制关闭，空闲后再提示。

自动化和 generic iPhoneOS 构建不能证明真实 BLE/Mesh TimeGet、TimeSet、最终 TimeStatus、Gateway Cloud 回读或真机视觉行为，以上仍需真实 Gateway 验收。

## 预计改动范围

- `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`
- `Tests/Device/GatewayDetailClockCoreTests.swift` 或新增聚焦的自动提示状态测试
- `Tests/Device/GatewayDetailClockRuntimeContractTests.swift`
- `scripts/check_gateway_information_time.sh`（仅在确认现有资源参数已失效后做聚焦修正）

预计无需修改：

- 现有中英文文案；
- `GatewayDetailClockCoordinator` 的 Mesh TimeGet/TimeSet、绑定、回读校验和云同步逻辑；
- `WiFiGatewayViewController` 的 Wi-Fi 网络业务逻辑；
- target 配置和依赖。

## 待确认

建议确认以下推荐口径后实施：

1. Wi-Fi 与 4G Gateway 都生效；
2. 复用现有 `requiresSync`，包括“读取失败/未知”也自动弹窗；
3. 每个 Proxy Ready Session 最多自动弹一次，`Later` 后同 Session 不再自动弹；
4. 自动弹窗不覆盖其他 Alert，等待展示条件恢复后再弹；
5. 用户已主动同步时取消待自动弹窗。
