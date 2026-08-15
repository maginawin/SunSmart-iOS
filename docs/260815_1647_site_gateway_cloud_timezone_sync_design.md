# Site Gateway Cloud Timezone Sync 设计规格

## 1. 文档状态

- 日期：2026-08-15
- 状态：产品与技术设计已确认，等待书面规格审核
- 工程：SunSmart iOS UIKit
- 入口：进入 Site 后的 `Time zone sync status` 弹窗
- UI 范围：弹窗标题、`GATEWAYS` 区域、失败统计、Footer 和容纳动态列表所需的弹层布局
- 接口：`/sitespace/gateway/datetime/update`、`/sitespace/request/status`

本规格只定义设计与实施边界，不包含业务代码修改、Git commit、push 或 merge。

## 2. 目标

进入 Site 并取得可信的 Cloud Site、Space 和 Gateway 快照后，App 在现有 Site timezone 仲裁基础上：

- 按 Owner / Editor Spaces 权限得到授权 Gateway。
- 比较每个授权 Gateway 的有效 timezone offset 与最终 Site timezone offset。
- 在 `Time zone sync status` 弹窗中展示全部授权 Gateway。
- 只向服务器提交需要同步的 Gateway MAC。
- 通过 requestId 每 3 秒获取实时结果。
- 在 3 分钟内逐项展示 `Pushing…`、`Synced`、`Failed`。
- 所有结果收敛前禁止关闭弹窗，收敛后只通过 `DONE` 关闭。
- 失败 Gateway 继续由现有现场 Bluetooth Review sync 流程承接。

## 3. 成功标准

- 不扩大非 Owner 的 Gateway 权限范围。
- 服务器始终使用已经确认的 Cloud Site timezone 下发 Gateway。
- 已经一致的 Gateway 不重复进入下发 body。
- Gateway 行、Header 数量、No gateways 和失败统计使用同一份状态真值。
- 单次状态接口失败不会让全部 Gateway 过早失败。
- 所有异步回调受 session 隔离，取消或关闭后的迟到结果不能更新 UI。
- HTTP 成功不被误当作 Mesh Node timestamp/timezone 的本地真值。
- 四个品牌 target 的资源、本地化和构建保持一致。

## 4. 当前行为边界

现有弹窗并非只在 App 向 Cloud 上传 Site timezone 时出现。以下三类可见决策均保留：

1. App 与 Cloud Site timezone 已一致，但授权 Gateway 存在待同步项。
2. Cloud Site timezone 胜出并成功更新 App。
3. App Site timezone 胜出并成功更新 Cloud。

Visitor 继续静默采用 Cloud Site 数据，不展示弹窗，也不进入 Gateway 自动同步。

如果 App 与 Cloud Site timezone 已一致，并且全部授权 Gateway 也已一致，继续沿用现有 noAction：不展示弹窗。`有授权 Gateway、无待同步项` 和 `No gateways` 的结果分支，只用于弹窗已经因为 Site 更新场景而需要展示的情况。

## 5. 已确认业务规则

### 5.1 Gateway 阶段的前置条件

Gateway 下发只在 Cloud Site timezone 已经可信时开始：

- Site 已一致：无需额外 Site 更新，直接开始 Gateway 阶段。
- Cloud 更新 App：本地 Site timezone 持久化成功后开始 Gateway 阶段。
- App 更新 Cloud：服务器 Site timezone 更新成功后开始 Gateway 阶段。
- 任一需要执行的 Site 更新失败：不得调用 Gateway 下发接口。

Site 更新失败时，原本已经一致的 Gateway 保持 `Synced`；本次需要同步的 Gateway 全部转为 `Failed`。

### 5.2 权限范围

- Owner：使用远端 Site 快照中的全部有效 Gateway MAC。
- 非 Owner 且拥有 Editor Spaces：只使用 Editor Spaces 的有效 `gatewayId` 集合。
- 同时拥有 Editor 与 Visitor Spaces：只使用 Editor Spaces 绑定的 Gateway。
- 只有 Visitor Spaces：授权 Gateway 数量为零。
- 同一 Gateway 关联多个 Space 时按规范化 MAC 去重。
- 未知 role 不提升为 Editor。

### 5.3 列表与请求目标

- 弹窗展示全部授权 Gateway。
- Header 数量等于去重后的授权 Gateway 总数。
- 已与目标 timezone 一致的 Gateway 初始即显示 `Synced`。
- 不一致、缺失或无效 timezoneOffset 的 Gateway 初始显示 `Pushing…`。
- 下发 body 只包含初始为 `Pushing…` 的 Gateway MAC。
- 授权 Gateway 大于零但没有待同步项时，不调用下发接口，全部显示 `Synced` 并立即展示 `DONE`。
- 只有授权 Gateway 数量为零时展示 No gateways 空状态。
- 失败统计只计算本次待同步目标中最终为 `Failed` 的 Gateway。

## 6. 架构选择

采用独立 Target Builder、API Client、Gateway Sync Coordinator 和 Overlay 展示模型的分层方案。

不把 3 分钟 Gateway 轮询合并到现有 Site timezone Coordinator，也不在 SiteViewController 中直接维护定时器和原始状态字典。

### 6.1 Site timezone Policy / Coordinator

继续负责：

- App / Cloud Site timezone 仲裁。
- Site 本地持久化。
- 必要的 Site Cloud 更新。
- 输出最终 Site 结果和目标 timezone。

不负责 Gateway 下发或轮询。

### 6.2 Gateway Target Builder

输入：

- 最终可信的 Site timezone。
- 导入前解析的远端权限与 Gateway 快照。
- Site 导入后可用的本地 GatewayModel / Node 信息。
- 当前 SiteViewController 生命周期内的临时成功 offset override。

输出：

- 全部授权 Gateway 的稳定展示行。
- 实际需要发送接口的 MAC 子集。

Target Builder 不发送请求，也不持有 UIKit View。

### 6.3 Gateway Timezone API Client

只负责：

- 调用 `/sitespace/gateway/datetime/update`。
- 调用 `/sitespace/request/status`。
- 严格解析 requestId。
- 将状态响应转换为标准化 Gateway 状态事件。

API Client 不维护轮询节拍、超时或 UI。

### 6.4 Gateway Sync Coordinator

只负责：

- 一次性下发待同步 MAC。
- 3 秒轮询节拍。
- 180 秒总超时。
- 单项状态合并和终态不可逆。
- 网络错误重试。
- 取消、后台恢复和 session 隔离。
- 输出完整、不可变的展示快照。

### 6.5 Overlay Gateway Status View

只根据展示模型渲染：

- Gateway Header。
- Gateway 行。
- No gateways。
- 失败统计。
- Footer 显隐。

它不访问网络，也不推导权限。

### 6.6 SiteViewController

只负责串联：

1. Site 加载与导入。
2. Site timezone 阶段。
3. Target Builder。
4. Gateway Sync Coordinator。
5. Overlay 生命周期和导航锁。
6. Review sync 即时状态。
7. 最终一次静默 Site 刷新。

## 7. Gateway 目标构建

### 7.1 身份规范化

- 匹配键忽略 MAC 大小写和首尾空白。
- 对外发送保留服务器提供的原始非空 MAC。
- 不在没有服务端契约的情况下擅自删除冒号或短横线。
- Owner 远端对象缺失有效 MAC 时无法形成可执行目标，不计入授权列表，并记录非敏感诊断信息。
- Editor Space 的有效 gatewayId 即使暂时缺少对应 `gateways[]` 对象，也保留为授权目标；其 timezone 未知，因此需要同步。

### 7.2 去重与冲突

- 相同规范化 MAC 只产生一行。
- 使用第一次出现的位置作为远端顺序。
- 重复对象的 offset 不一致时，该 Gateway 视为需要同步。
- 接口 body 中每个规范化 MAC 只出现一次。

### 7.3 名称

- 优先使用按 MAC 匹配到的本地 GatewayModel.name。
- 名称去除首尾空白后为空，或本地模型缺失时，显示接口发送用 MAC。
- 名称只用于 UI，不参与身份判断。

### 7.4 有效 offset

- 目标为最终 SiteTimeZoneValue.offsetMinutes。
- 远端 timezoneOffset 使用 `(value - 64) × 15` 转换为分钟。
- Bool、小数、负数、超出 UInt8、空值或不可解析值均为未知。
- 本地 Gateway 存在尚未上传的可信 offset 时，沿用当前 dirty override 口径参与比较。
- 本次服务器状态已确认成功的 Gateway，在当前 SiteViewController 生命周期内使用目标 offset 作为临时 override。

有效 offset 优先级从高到低为：

1. 当前 SiteViewController 生命周期内的服务器成功 override。
2. 完整 Site 导入前捕获并在导入后恢复的本地可信 dirty offset。
3. 当前远端 Gateway snapshot offset。

本地 dirty offset 必须在完整 Site 导入前捕获，不能在可能已被远端覆盖后才重新读取。

## 8. 主数据流

### 8.1 Site 加载

1. 调用现有 `/sitespace/get/siteprops`。
2. 在完整导入前捕获 App Site props 和远端权限/Gateway 快照。
3. 由现有 Policy 决定 Site timezone 结果。
4. 完整导入 Site，使本地 Gateway 名称和模型可用。
5. 展示现有 checking 状态，并执行 Site timezone 阶段。

### 8.2 Site 阶段完成

- Site 成功：构建 Gateway 目标并进入 Gateway 阶段。
- Site 失败：构建 Gateway 目标，但不调用 Gateway API；待同步项全部失败。
- Visitor 或 noAction：保持现有静默/不展示路径。

### 8.3 Gateway 阶段

- 无授权 Gateway：展示 No gateways 和 `DONE`。
- 有授权 Gateway、无待同步项：全部 `Synced`，展示 `DONE`。
- 有待同步项：全部待同步行显示 `Pushing…`，调用下发接口。
- 下发失败：待同步项全部 `Failed`，展示失败统计和 `DONE`。
- 下发成功：取得 requestId 并开始轮询。
- 全部终态或超时：停止轮询，更新 Review sync，显示 `DONE` 并静默刷新 Site。

## 9. 接口契约

### 9.1 Gateway timezone 下发

- Method：POST。
- Path：`/sitespace/gateway/datetime/update`。
- Body：siteId 和待同步 Gateway MAC 数组。
- 不传 timezone；服务器使用当前 Cloud Site timezone。
- 所有待同步 MAC 一次性发送，不在 App 端拆批。

成功响应必须满足：

- 业务 code 成功。
- data 存在合法 requestId。
- requestId 是可无损转换为正 Int64 的整数值；兼容整数 NSNumber 和纯整数字符串。
- Bool、小数、零、负数、越界或缺失值均视为下发失败。

### 9.2 Gateway 状态查询

- Method：POST。
- Path：`/sitespace/request/status`。
- Body：合法 requestId。
- data 预期为 Gateway MAC 到状态字符串的对象数组。

MAC 处理：

- 忽略大小写和首尾空白。
- 非本次待同步目标忽略。
- data 中缺失某目标时保持原状态。

状态处理：

- `Requested`：保持 `Pushing…`。
- `Succeed`：转为 `Synced`。
- `Failed`：转为 `Failed`。
- `Expired`：转为 `Failed`。
- `NIL`、JSON null、缺失或其他值：不更新。

状态字符串只识别上述契约值；未知拼写不猜测、不映射。

## 10. 状态机

### 10.1 单项状态

UI 只暴露三个状态：

- `Pushing…`
- `Synced`
- `Failed`

初始已一致 Gateway 直接为 `Synced`。待同步 Gateway 从 `Pushing…` 进入 `Synced` 或 `Failed`。

`Synced` 和 `Failed` 均为不可逆终态。迟到的 `Requested`、未知值或后续冲突状态不能回退终态。

### 10.2 重复与冲突结果

- 同一轮同一 MAC 的状态全部一致：正常处理。
- 同一轮同时出现 `Requested` 与一个终态：采用终态。
- 同一轮同时出现 `Succeed` 与 `Failed` / `Expired`：视为服务端冲突，本轮不更新该 Gateway，继续轮询。
- Gateway 已终态后，后续重复结果忽略。

### 10.3 批次完成

- 没有待同步目标：立即完成。
- 所有待同步目标进入终态：立即完成并停止轮询。
- 到达总 deadline：所有剩余 `Pushing…` 一次性转为 `Failed`，批次完成。

## 11. 轮询、超时与取消

- 从成功取得合法 requestId 时开始计算 180 秒。
- 第一次状态请求在 3 秒后发送。
- 后续请求保持 3 秒节拍。
- 状态接口单次网络错误、业务失败或结构错误均视为本轮无结果，继续轮询。
- 不因单次失败重置 180 秒 deadline。
- 使用单调时钟，避免系统时间调整影响超时。
- App 进入后台时 deadline 继续流逝；恢复后先检查是否已经超时。
- requestId 不持久化，进程重启后不恢复旧批次。
- Controller 销毁时取消本地任务和 UI 回调。
- 每个批次使用唯一 session token；旧 session、取消后或页面关闭后的迟到结果全部忽略。

用户不能主动取消进行中的 Gateway 批次；生命周期取消只用于 Controller 销毁或进程结束等系统边界。

## 12. UI 设计

### 12.1 弹层结构

结果弹层改为底部弹层：

1. `Time zone sync status` 标题。
2. 现有 Site 状态区域。
3. Gateway 状态区域。
4. 可选失败统计卡。
5. 可选 `DONE` Footer。

Site 区域继续使用现有 Site timezone 结果语义，不因本功能重做。

### 12.2 Gateway Header

- 左侧：`GATEWAYS`。
- 右侧：授权 Gateway 总数。
- Header 不随 Gateway 行滚动。

### 12.3 Gateway 行

- 保持 Cloud 原始顺序。
- 左侧 16×16 状态图标。
- 中间 Gateway name，单行尾部截断。
- 右侧状态文案。
- 行之间使用现有项目分隔线风格。
- `Pushing…` 的 Loading 图标持续旋转。
- `Synced` 使用成功图标和辅助灰状态文字。
- `Failed` 使用失败图标和失败红状态文字。

优先复用现有项目图标、颜色、字体和尺寸；只有现有资源不能匹配 Figma 时才增加对应资源。

### 12.4 No gateways

只有授权 Gateway 数量为零时显示：

- `No gateways`
- `No gateways configured - no sync needed.`

此状态立即显示 `DONE`。

### 12.5 失败统计

失败数大于零时，在 Gateway 区域下方展示失败统计卡：

- 1 个失败：`1 gateway failed`
- 多个失败：`%d gateways failed`
- 引导语：`Sync on-site via Bluetooth to complete.`

中文使用完整本地化文案，不拼接多个翻译片段。

### 12.6 长列表

- 弹层向上增长时，顶部不得越过 `safeArea.top + 16pt`。
- 超过可用高度后，只滚动 Gateway 行列表。
- 标题、Site 区域、Gateway Header、失败统计和 Footer 保持可见。
- Footer 适配底部 safe area。

## 13. 关闭与导航锁

- 任一 Gateway 仍为 `Pushing…` 时不展示 Footer。
- 同步期间禁止导航栏返回、交互式侧滑返回、背景点击和其他 Overlay 关闭路径。
- 全部终态或 No gateways 时展示唯一 `DONE`。
- 删除当前 Gateway pending 状态的 `LATER` 和 `REVIEW SYNC` Footer。
- 点击 `DONE` 后依次关闭 Overlay、解除导航锁并继续现有 Site 入口后的导航。
- `DONE` 不等待静默 Cloud 刷新完成。

## 14. Review sync 与 Cloud 收敛

### 14.1 即时 Review sync

- 全部 Gateway 成功或本来已一致：立即隐藏 Site 页 Review sync。
- 存在失败：Review sync 只保留失败 Gateway 数量。
- Site 更新失败：本次待同步项全部失败，Review sync 保留这些失败目标。
- No gateways：Review sync 隐藏。

失败 Gateway 继续通过现有 `SyncGatewaysViewController` 执行现场 Bluetooth 同步。

### 14.2 临时成功 override

服务器状态返回 `Succeed` 后，当前 SiteViewController 生命周期内把该 MAC 的有效 offset 临时视为目标 Site offset：

- 防止随后一次 Cloud 快照仍旧时立即重新显示待同步。
- 只影响 Gateway timezone 比较和 Review sync 投影。
- 不伪造 GatewayModel dirty generation。
- 不修改 Mesh Node timestamp/timezone。
- Cloud snapshot 返回目标 offset 后移除对应 override。
- SiteViewController 销毁时全部清除。

### 14.3 静默刷新

- Gateway 批次进入终态后最多触发一次静默 `/get/siteprops`。
- 刷新不阻塞 `DONE`。
- 刷新失败不回退本次 UI 终态。
- 失败 Gateway 仍保持 Review sync。
- 下一次独立进入 Site 时重新以新的 Cloud 快照和本地可信 dirty 状态判断。

## 15. 国际化与可访问性

- 所有新增或修改的用户可见文案同时提供 English 和简体中文。
- 标题改为 `Time zone sync status`。
- 成功状态统一使用 `Synced`，不使用 `Syned`。
- 英文失败数正确区分单数和复数。
- `Pushing…`、`Synced`、`Failed`、No gateways 和失败引导使用完整本地化 Key。
- Gateway 行为 VoiceOver 提供名称和当前状态。
- Loading 动画只承担视觉表达，状态文字仍提供完整语义。
- Dynamic Type 增大时不能遮挡 Footer；必要时 Gateway 行增加高度，但仍保持列表滚动边界。

## 16. 错误处理矩阵

| 场景 | Gateway 请求 | 待同步项结果 | Footer | Review sync |
|---|---|---|---|---|
| Site 已一致 | 发送 | 按轮询结果 | 全部终态后 `DONE` | 只保留失败项 |
| Cloud 更新 App 成功 | 发送 | 按轮询结果 | 全部终态后 `DONE` | 只保留失败项 |
| App 更新 Cloud 成功 | 发送 | 按轮询结果 | 全部终态后 `DONE` | 只保留失败项 |
| Site 更新失败 | 不发送 | 全部失败 | `DONE` | 保留全部待同步项 |
| 无授权 Gateway | 不发送 | 无 | `DONE` | 隐藏 |
| 全部初始已一致 | 不发送 | 全部成功 | `DONE` | 隐藏 |
| 下发接口失败 | 已失败 | 全部失败 | `DONE` | 保留全部待同步项 |
| requestId 非法 | 不轮询 | 全部失败 | `DONE` | 保留全部待同步项 |
| 状态接口单次失败 | 继续轮询 | 不变 | 隐藏 | 暂不更新 |
| 部分成功、部分失败 | 停止于全部终态 | 分项展示 | `DONE` | 只保留失败项 |
| 180 秒超时 | 停止 | 剩余项失败 | `DONE` | 只保留失败项 |

## 17. 文件边界

预计修改：

- `SunSmart/Common/Network/NetowrkReqeustApi.swift`
- `SunSmart/Main/Site/Controller/SiteViewController.swift`
- `SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift`
- `SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift`，仅在 Review sync 投影需要新的显式输入时做聚焦修改
- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`
- `SunSmart.xcodeproj/project.pbxproj`

预计新增聚焦文件：

- Gateway target / display state 纯模型与 Builder。
- Gateway timezone API Client 与 response parser。
- Gateway timezone Sync Coordinator。
- Overlay Gateway status list view。
- 对应 Site 测试文件。

正式实施计划必须在核对当前 Xcode group 命名和既有测试接入方式后锁定最终文件名，不把新逻辑塞入无关模块。

## 18. 自动化测试

### 18.1 Target Builder

- Owner 全部 Gateway。
- Editor / Visitor 混合 Space。
- 只有 Visitor。
- 重复 MAC 和重复 Space 绑定。
- Editor gatewayId 缺少远端 Gateway 对象。
- Owner Gateway 缺失有效 MAC。
- 名称缺失回退 MAC。
- Cloud 顺序。
- offset 已一致、不同、缺失、非法。
- local dirty 和临时成功 override 优先级。

### 18.2 API Parser

- 合法 Int / NSNumber / 纯整数字符串 requestId。
- Bool、小数、零、负数、越界、缺失 requestId。
- 合法状态数组。
- MAC 大小写和空白。
- 缺失目标、额外目标、重复目标。
- `NIL`、null、未知值。
- 同轮成功/失败冲突。

### 18.3 Coordinator

- 3 秒首次轮询和后续节拍。
- 180 秒总 deadline。
- 下发接口直接失败。
- 单次状态请求失败后继续。
- 全部终态提前结束。
- 部分终态后继续等待。
- 超时只把剩余项转失败。
- 取消、后台恢复和迟到响应。
- 旧 session 结果隔离。

### 18.4 UI / Contract

- 标题和本地化文案。
- Header 授权总数。
- 三种 Gateway 行状态和 Loading 动画。
- No gateways。
- 英文失败数单复数。
- 进行中无 Footer。
- 终态只有 `DONE`。
- 导航锁与解除顺序。
- 长列表滚动和顶部 safe area。
- Review sync 成功清除与失败保留。
- 临时成功 override 和静默刷新。

### 18.5 回归

- SiteEntryTimeZoneSyncPolicyTests。
- SiteEntryTimeZoneSyncCoordinatorTests。
- SiteEntryTimeZoneSyncContractTests。
- SiteTimeZoneUIContractTests。
- Site props API / persistence tests。
- 现有 SyncGateways Context、State 和 UI contracts。

## 19. 静态与构建验证

- English 和简体中文 Localizable.strings 语法检查。
- `git diff --check`。
- 直接使用 `xcodebuild`，不使用 shell 包装、不重定向日志、不使用 Simulator。
- generic iPhoneOS Debug 无签名构建：
  - SunSmart
  - Archipelago
  - SLG Sync Plus
  - SylSmart

构建成功只证明静态集成，不代表真实服务器或 Gateway 端到端成功。

## 20. 真服务器与真机验收

- Owner 与 Editor Spaces 的真实权限范围。
- `/sitespace/gateway/datetime/update` body 的 MAC 格式和数量上限。
- requestId 实际类型与范围。
- 状态值大小写、未知值和重复项。
- 直接失败、网络抖动、部分成功和真实 3 分钟超时。
- `Succeed` 后 Cloud Gateway timezoneOffset 的更新时间和 `/get/siteprops` 可见延迟。
- 重复进入 Site 时服务端下发是否幂等。
- 后台/前台、进程结束和 Controller 生命周期。
- 长 Gateway 列表、safe area、Dynamic Type 和 VoiceOver。
- 失败后现有现场 Bluetooth Review sync 路由。
- 四品牌 target 的页面、文案和资源。

## 21. 本期不包含

- requestId 持久化或 App 重启后恢复轮询。
- 用户主动取消正在进行的批次。
- 超时或失败后的自动重新下发。
- App 端把一个 Gateway 批次拆为多个请求。
- 修改服务器接口、权限或 Auth 信息。
- 根据 HTTP 结果直接写入 Mesh Node timestamp/timezone。
- 重构现场 BLE SyncGatewaysViewController。
- 重构无关 Site、Space、Gateway、BLE 或 Cloud 模块。

## 22. 实施约束

- 保持改动聚焦，不覆盖当前 worktree 的既有功能。
- 优先复用现有 UIKit、SnapKit、颜色、字体、图标和动画能力。
- 新增用户可见文案必须国际化。
- 新文件、资源和本地化必须核对四个品牌 target。
- 网络层不得新增 Auth 信息。
- 状态真值、UI 投影和副作用必须分离，便于确定性测试。
- 正式实施必须先写失败测试，再完成最小实现。
- 自动化、构建、真服务器和真机验收结论必须分别报告。
