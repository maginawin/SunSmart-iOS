# SLG Sync Plus 全节点 TimeSet 触发与时区来源分析

## 结论

当前 SLG Sync Plus Target 的“给所有设备同步 TimeSet”路径，是 `DevicesViewController` 监听到本页面实例生命周期内**首次 Mesh 连接成功**后，在满足日程条件时延迟 3 秒执行的一次广播；它不是周期同步，也不会在同一控制器实例的每次断线重连后重复执行。

TimeSet 的时间与时区来源需要分开理解：

- 时间点使用发送时的 `Date()`，即手机系统提供的当前绝对时间。
- 时区偏移优先使用本地 `SiteData.timezone` 保存的 Site 固定 UTC offset。
- Site 不存在、Site timezone 缺失、格式无效或 offset 无法按 Mesh 规则编码时，才回退到发送时手机 `TimeZone.current` 的 offset。
- 如果手机回退 offset 也不能编码，广播不会发送。

因此，时区结论不是简单的“手机”或“Site”二选一，而是：**Site timezone 优先，手机 timezone 兜底**。

## SLG Target 是否执行这段逻辑

SLG Sync Plus 的 Sources Build Phase 同时包含：

- `DevicesViewController.swift`
- `SiteTimeSetMessageFactory.swift`
- `SiteTimeZoneValue.swift`

Debug 配置定义 `DEBUG SLGSync`，Release 配置定义 `SLGSync`。全节点广播逻辑本身没有被 `#if SLGSync` 排除，所以 Debug 与 Release 都会执行；只有 5 秒后的额外调试单播被 `#if DEBUG` 限制。

## 触发链路

```text
进入 Space
  -> DevicesViewController.viewDidLoad()
  -> 注册 isMeshNetworkConnected KVO（只监听 new value）
  -> 收到连接状态变化且当前为 connected
  -> firstConnectionNetwork 必须仍为 true
  -> 立即将 firstConnectionNetwork 设为 false
  -> 同时满足：
       1. 至少一个 realNode 的 scheduleIds 非空
       2. 全局 schedules 至少有一个 enabled == true
  -> 延迟 3 秒
  -> 再次检查 Mesh 当前仍已连接
  -> 按 space.siteId 解析时区并生成 TimeSet
  -> 发送到 .allNodes
  -> 立即记录 space.lastSyncDateTimestamp 并本地保存
```

### 精确边界

1. “首次”是每个 `DevicesViewController` 实例的首次连接成功，不是 App 安装后的永久首次。
2. `firstConnectionNetwork` 在安排 3 秒任务前就被设为 `false`。如果 3 秒后已经断开，`syncTimeNodes()` 会退出；同一实例后续重连不会补发。
3. 两个日程条件是分别检查的，没有验证“带 `scheduleIds` 的节点”与“启用日程”一定属于同一条关联关系。
4. 目标地址是 Mesh 固定组地址 `.allNodes`，并未先筛选支持 Time Setup Server 的节点。所有节点都会收到广播，但只有支持并处理 Time Set 的设备才会实际应用。
5. 这里通过无回调的通用发送接口入队，没有等待 `TimeStatus`。`lastSyncDateTimestamp` 表示 App 已入队发送，不代表所有设备确认成功。
6. Debug 构建在首次连接条件满足后，还会于第 5 秒对第一个日程节点做一次额外单播调试；Release 没有该动作。

## 时区解析规则

`SiteTimeSetMessageFactory.makeMessage(siteID:)` 先从本地数据库加载 Site，再解析 `site.timezone`。

### Site 路径

合法存储格式是：

```text
IANA identifier (UTC+/-HH:mm)
```

例如 `Asia/Singapore (UTC+08:00)`。TimeSet 真正使用的是括号中的固定 offset；IANA identifier 当前不参与发送时的 DST 重新计算。offset 必须是 15 分钟的整数倍，并在 Mesh `tzOffset` 可编码范围内。

### 手机回退路径

以下情况会回退手机时区：

- 找不到 Site；
- `site.timezone` 为 nil 或空字符串；
- 存储格式无效；
- Site offset 不是 15 分钟整数倍或超出 Mesh 可编码范围。

回退时读取 `TimeZone.current.secondsFromGMT(for: date)`，同样要求 15 分钟对齐且可编码。失败时 `makeMessage` 返回 nil，本次广播被跳过。

## 当前实现的业务含义

- 正常 Site timezone 数据有效时，即使手机位于另一个时区，广播仍使用 Site 保存的 UTC offset。
- Site timezone 数据异常时，App 不会 fail closed，而是可能悄悄用手机时区继续广播；Debug 日志会打印 fallback reason，Release 不打印。
- Site 保存的是带 IANA 名称的固定 offset 快照。若地区进入或退出夏令时，但 Site 的存储值尚未刷新，TimeSet 仍会使用旧的固定 offset。
- 该广播仅由“首次 Mesh 连接 + 日程条件”触发；修改 Site timezone 本身并不会直接触发这条 `.allNodes` 广播。

## 验证

已执行现有静态/单元契约：

- `zsh scripts/check_site_timeset_message_factory.sh`：通过
- `zsh scripts/check_site_timeset_call_sites.sh`：通过

本次为只读分析，没有修改业务代码，也没有执行 iOS 构建或真实 Mesh 抓包。尚未验证真实 SLG 设备是否全部接收、哪些型号处理广播 TimeSet、`TimeStatus` 响应情况及断线窗口行为。
