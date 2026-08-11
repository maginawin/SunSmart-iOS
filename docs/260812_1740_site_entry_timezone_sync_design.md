# Site 进入时区同步检查设计

## 1. 文档状态

- 日期：2026-08-12
- 状态：设计章节已确认，等待正式规格复核
- 采用方案：方案 A——独立检查协调器、纯判定策略和专用居中 Overlay
- 前置分析：`docs/260812_1527_site_entry_timezone_mismatch_gap_analysis.md`

## 2. 背景与目标

App 进入 Site 页面时会请求 `/sitespace/get/siteprops`。本功能在该请求首次成功后，对当前 Site 的本地与服务器 timezone 进行版本仲裁；仅当本次响应表明当前用户是 Site Owner 或 Site Editor，且有效 timezone 需要收敛时，展示同步状态弹窗并执行必要的本地持久化或服务器回写。

目标包括：

- 以明确的 timestamp 规则选出 Site timezone 真值。
- 服务器值胜出时只更新本地，不反向上传。
- 本地值胜出时由 App 显式上传，并正确维护 timezone pending。
- 按 Figma 展示 checking 与结果弹窗。
- 只读展示 Gateway timezone 同步概况，不执行 Gateway 同步。
- 保持请求失败、无权限、timezone 相同等既有路径不变。

## 3. 本期范围

### 3.1 包含

- Site 级 timezone 有效性校验、版本仲裁、本地持久化和必要的服务器回写。
- Site Owner/Editor 权限判断。
- 每个 `SiteViewController` 实例一次的进入检查。
- checking 最短 1 秒、最长 30 秒及超时失败处理。
- Site timezone 结果与 Gateway 只读同步概况展示。
- English、简体中文和四品牌 target 适配。

### 3.2 排除

- Gateway Time Zone SET。
- BLE/Mesh 连接和附近 Gateway 扫描。
- `Review sync`、Gateway 列表、单个 Gateway 同步、重试和完成流程。
- Gateway 同步完成度的写入或变更。
- App 进入后台或网络恢复时重复检查。

Gateway 实际同步后续单独立项。

## 4. 设计依据

### 4.1 当前请求链路

- `SiteViewController.viewDidLoad()` 在满足既有条件时调用 `loadSiteRequest()`。
- `.siteInfo(siteId:)` 对应 `/sitespace/get/siteprops`。
- 成功响应当前会通过 `SiteData.update(siteJsonData:)` 导入并刷新 Site。
- 同一请求也可能由下拉刷新、网络恢复等入口触发，因此本功能不能绑定到每一次 `loadSiteRequest()`。

### 4.2 Figma

- checking：[节点 399:11417](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=399-11417&t=oN7SOw4tvoiO4yHD-11)
- 无 Gateway 结果：[节点 399:11389](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=399-11389&t=oN7SOw4tvoiO4yHD-11)
- 文件内相关变体：`399:11424`（Gateway 待同步）和 `399:11362`（已同步）。

本期沿用这些节点的视觉结构，但所有结果态只保留 `GOT IT`，不提供 `Review sync`。

## 5. 核心决策规则

### 5.1 权限

权限只取本次成功 `/get/siteprops` 响应中当前 Site 的 `role`：

- Owner、Editor：允许进入 timezone 检查。
- Visitor 或无法解析的 role：维持现状。
- 不使用请求前本地权限缓存。
- 不将任一 Space 的 Owner/Editor 权限等同为 Site 权限。

### 5.2 timezone 有效性

只有可解析为有效 IANA timezone identifier 的值参与仲裁：

| 本地 timezone | 服务器 timezone | 处理 |
|---|---|---|
| 有效 | 有效 | 进入内容与 timestamp 比较 |
| 无效 | 有效 | 采用服务器值并持久化到本地，不上传 |
| 有效 | 无效 | 采用本地值并上传服务器 |
| 无效 | 无效 | 维持现状，不提示、不上传 |

比较前对 timezone 做规范化，避免空格或等价格式造成误判。

### 5.3 timestamp 仲裁

当两端 timezone 均有效时：

| 条件 | 最终 timezone | 后续动作 |
|---|---|---|
| 两端 timezone 相同 | 相同值 | 不提示、不上传 |
| 服务器 `updateTimestamp` 严格大于本地 `site.lastUpdate` | 服务器值 | 持久化到本地，不上传 |
| 服务器 timestamp 小于本地 timestamp | 本地值 | 显式上传服务器 |
| timestamp 相等且 timezone 不同 | 本地值 | 显式上传服务器 |

本地值胜出时：

- 显式创建 timezone pending/update snapshot，不只依赖现有 `needUploadCloud` 推导。
- 上传使用严格大于本地和服务器 timestamp 的新 `updateTimestamp`。
- 上传成功后清除对应 pending；失败或超时则保留 pending。

## 6. 架构

### 6.1 Site 页面入口

`SiteViewController` 只负责：

- 在整包导入前捕获本地 timezone、`lastUpdate` 和 pending 快照。
- 将本次成功响应的只读快照交给协调器。
- 提供 Overlay 展示入口和页面生命周期信号。

控制器不直接承担权限、timestamp 仲裁、计时或结果拼装。

### 6.2 纯判定策略

纯策略接收：

- 请求前本地 Site 快照。
- 本次响应的 Site role、timezone、`updateTimestamp` 和 Gateway 只读状态。

策略输出三类决策：

- 不处理。
- 采用服务器 timezone。
- 采用本地 timezone 并上传。

策略不访问数据库、不发请求、不操作 UI，便于覆盖完整决策矩阵。

### 6.3 进入检查协调器

每个 `SiteViewController` 实例拥有一个独立协调器，负责：

- 仅消费首次成功的进入请求；刷新、网络恢复、Gateway 关联刷新和前后台切换不重复触发。
- 等待既有 HUD 或业务弹窗结束后展示 checking。
- 管理最短 1 秒和最长 30 秒计时。
- 在弹窗期间锁定导航栏返回和侧滑返回，并在结束后恢复原状态。
- 执行持久化或上传并向 Overlay 发布终态。
- 取消或忽略超时后的迟到响应。
- 在控制器释放或 Site 被外部切换时清理任务和 Overlay。

### 6.4 持久化与上传

复用项目现有 Site 持久化和 API 能力，不复制完整 Site 导入逻辑：

- 服务器值胜出：确认本地持久化成功后才能显示 `Updated from server`。
- 本地值胜出：显式上传 timezone；成功显示 `Updated to server`，失败显示 `Failed to update server`。
- 采用服务器值时不发送 timezone 更新请求。

### 6.5 专用 Overlay

新增专用全屏 Overlay，独立于 `SRAlertView` 和 Edit Site 的 `SiteTimeZoneSyncStatusView`：

- checking：全屏遮罩、居中卡片、loading、`Checking sync status...`，无按钮。
- result：展示 Site timezone 结果、Gateway 只读状态和 `GOT IT`。
- checking 与 result 均不可点击遮罩关闭。
- 不调用 `SRAlertView.show()`，不主动关闭其他业务弹窗。

## 7. 主数据流

1. 页面发起首次进入用 `/get/siteprops` 请求，并在导入前保存本地快照。
2. 请求失败时终止新流程，既有页面逻辑保持不变。
3. 请求成功后解析远端只读快照，并以本次 Site `role` 执行权限判断。
4. 纯策略输出“不处理”时，继续既有导入和刷新流程，不显示新弹窗。
5. 需要收敛时，将当前页面实例标记为已检查；等待现有 HUD 或业务弹窗结束。
6. 展示 checking，同时启动 1 秒最短计时、30 秒总超时并锁定返回。
7. 按策略采用服务器值并本地持久化，或采用本地值并上传服务器。
8. 操作完成且 checking 已显示至少 1 秒后进入结果态。
9. 30 秒仍无终态时进入失败态，取消底层任务或忽略后续回调。
10. 用户点击 `GOT IT` 后移除 Overlay、取消计时并恢复进入前的导航状态。

## 8. 状态与文案

### 8.1 Site 行

| 结果 | 文案 | 数据行为 |
|---|---|---|
| 服务器值采用并落库成功 | `Updated from server` | 不上传 |
| 本地值上传成功 | `Updated to server` | 清除 timezone pending |
| 采用服务器后本地持久化失败 | `Failed to update server` | 不显示成功语义 |
| 本地值上传失败 | `Failed to update server` | 保留 timezone pending |
| 30 秒超时 | `Failed to update server` | 本地待上传值保留 pending，忽略迟到响应 |

### 8.2 Gateway 行

Gateway 行只读取 `/get/siteprops` 已返回的数据：

| 状态 | 文案 |
|---|---|
| Site 无 Gateway | `No gateways to sync` |
| 待同步数量大于 0 | `N gateways need time zone sync` |
| 全部已同步 | `All gateways are in sync` |
| 同步标识缺失或无法解析 | `All gateways are in sync` |

Gateway 行不改变 Site timezone 决策，也不触发 Gateway 同步。

Figma 注释和当前源码只定义了“Gateway 已同步/未同步标识”的语义，没有给出服务器 JSON 字段名。实现必须把字段映射隔离在响应解析器中；只有取得正式后端字段契约后才接入计数。字段契约不可用时不得猜测或使用本地 Mesh 状态替代，统一按“同步标识缺失”处理。

### 8.3 本地化

所有用户可见文案必须使用本地化 Key，并同时提供：

- English（默认）。
- 简体中文（zh-CN）。

显示的 UTC offset 和 IANA timezone 必须来自当前采用的实际 timezone，不得写死。新增本地化和资源需检查 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target。

## 9. 计时、互斥与生命周期

- 1 秒最短展示和 30 秒超时均从 checking 实际显示时开始计算。
- 操作在 1 秒内完成：等待满 1 秒后显示结果。
- 操作在 1 至 30 秒内完成：完成后立即显示结果。
- 操作达到 30 秒：显示失败结果，不再接受后续回调改变 UI 或 pending 决策。
- checking 到 result 关闭期间禁止导航栏返回和侧滑返回。
- Overlay 关闭后恢复展示前的导航状态，不应假定进入前手势一定开启。
- 用户不能通过遮罩关闭 checking 或 result；result 仅通过 `GOT IT` 关闭。
- 页面被外部释放或 Site 切换时，立即取消任务并清理 Overlay，不展示迟到结果。

## 10. 验收矩阵

| 场景 | 预期 |
|---|---|
| `/get/siteprops` 失败 | 完全维持现状 |
| Visitor，timezone 不同 | 不提示、不上传 |
| Owner/Editor，timezone 相同 | 不提示、不上传 |
| 服务器 timestamp 更新且 timezone 不同 | 采用服务器值、本地落库、不上传、显示 `Updated from server` |
| 服务器 timestamp 不更新且 timezone 不同 | 采用本地值并上传 |
| timestamp 相等且 timezone 不同 | 采用本地值并上传 |
| 本地上传成功 | 显示 `Updated to server`，清除 pending |
| 本地上传失败 | 显示 `Failed to update server`，保留 pending |
| checking 达到 30 秒 | 显示失败，保留适用的 pending，忽略迟到响应 |
| 同一页面实例再次刷新或网络恢复 | 不重复检查或弹窗 |
| 离开后重新进入并创建新实例 | 允许再次检查 |
| 无 Gateway | 显示 `No gateways to sync` |
| Gateway 有待同步 | 显示动态数量，只保留 `GOT IT` |
| Gateway 已同步、标识缺失或解析失败 | 显示 `All gateways are in sync` |

## 11. 测试与验证

### 11.1 自动测试

- 纯策略：role、timestamp 大于/等于/小于、timezone 有效性和 Gateway 结果映射。
- 协调器：每实例一次、HUD/业务弹窗顺序、1 秒下限、30 秒上限、迟到响应、取消和导航恢复。
- 持久化/API：服务器值采用后不上传；本地值采用后显式上传；timestamp 严格更新；pending 成功清除、失败保留。
- UI 契约：checking/result 状态、`GOT IT`、无 `Review sync`、遮罩不可关闭及本地化 Key 完整性。

### 11.2 工程验证

- 运行 Site timezone 聚焦测试。
- 运行 `git diff --check`。
- 对 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 执行 generic iPhoneOS Debug 构建，禁用代码签名。
- 检查新增源码、本地化和资源的四 target membership。

### 11.3 人工验收

- 真机核对 Figma 视觉、动画、遮罩和导航锁定。
- 验证 English、简体中文、长 IANA timezone、Dynamic Type、iPad 和横竖屏。
- 使用真实服务器验证远端采用、本地上传、失败和 30 秒超时。
- 使用真实 Site Gateway 数据验证三个只读 Gateway 结果。

自动测试和构建通过只能证明静态契约与工程可编译，不能替代真实服务器、真机或 Gateway 端到端验收。

## 12. 完成标准

- 第 10 节验收矩阵全部具备对应自动测试或明确的人工验收项。
- 本期没有 Gateway 同步写操作和 `Review sync` 入口。
- 新功能不改变 Edit Site 既有 timezone 保存弹窗行为。
- 请求失败、Visitor、timezone 相同和两端 timezone 无效路径保持现状。
- 四品牌 target 构建通过，且验证结论明确区分自动验证与端到端验收。
