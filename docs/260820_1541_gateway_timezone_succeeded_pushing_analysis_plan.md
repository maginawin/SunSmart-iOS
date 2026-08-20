# Gateway timezone 返回 `SUCCEEDED` 后仍显示 `Pushing...` 的原因分析与修复计划

## 1. 结论

问题不在 Site timezone 上传，也不在 Gateway timezone 下发请求本身。日志证明这两步均已被服务器接受：

1. Site 属性更新返回 HTTP 200、业务码 200；
2. Gateway datetime update 返回有效 `requestId = 339`；
3. request status 返回 Gateway `EF725643A2B9 = SUCCEEDED`。

根因是 App 的 Gateway 状态解析器只识别 `SUCCEED`，不识别服务器实际返回的 `SUCCEEDED`。大小写归一化后，`SUCCEEDED` 变成 `succeeded`，仍然无法命中当前只包含 `succeed` 的分支，因此该 Gateway 状态被静默忽略。

最终表现为：HTTP 请求成功，但本地状态机没有收到可应用的成功状态，Gateway 行继续保持 `.pushing`，UI 继续显示 `Pushing...` 并重复轮询。

## 2. 完整状态链路

### 2.1 Edit Site 提交链路正常

- `SiteEditViewController.finishTimeZoneCommit` 创建 `SiteTimeZoneEditSyncCoordinator`、Gateway session 和 Cloud sync coordinator。
- `SiteTimeZoneEditSyncCoordinator` 先调用 `SitePropsEditCoordinator.submit` 更新服务器 Site timezone。
- Site 更新成功后，Gateway session 根据本地 Gateway 当前 offset 构造需要同步的目标。
- 需要同步的 Gateway 初始状态为 `.pushing`，随后调用 `/sitespace/gateway/datetime/update`。

日志中的 Site 更新和 Gateway datetime update 都成功，说明故障发生在 request status 返回之后。

### 2.2 request status 响应在解析阶段丢失

相关源码：

- `SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneAPIClient.swift`
- `SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneResponseParser.swift`
- `SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneSyncState.swift`
- `SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneSyncCoordinator.swift`

实际响应的关键数据为：

- Gateway ID：`EF725643A2B9`
- 状态：`SUCCEEDED`

解析器会先去除空白并转为小写，所以实际比较值是 `succeeded`。但当前成功分支只接受 `succeed`。因此：

1. Gateway ID 本身能够正常归一化为 `ef725643a2b9`，不是 MAC 大小写问题；
2. `succeeded` 被当成未知状态；
3. 当前条目被跳过；
4. 因为 `data` 的外层仍然是合法数组，解析器返回空数组，而不是解析错误；
5. API Client 把空数组当作一次成功的状态查询结果。

### 2.3 空状态数组不会结束轮询

`SiteGatewayCloudTimeZoneBatchState.apply` 只会在找到与当前 Gateway ID 匹配的已解析状态时更新行状态。空数组不会改变任何 Gateway：

- `.pushing` 不会变成 `.synced`；
- `hasPushing` 仍为 `true`；
- `canDismiss` 仍为 `false`；
- 因状态没有变化，`onUpdate` 也不会刷新 UI；
- Cloud sync coordinator 每 3 秒继续轮询。

当前协调器配置了 60 秒单调时钟超时。正常前台运行时，约 60 秒后剩余 `.pushing` 应被转成 `.failed`，而不是永久保持 `Pushing...`。因此用户所说的“一直”对应的是在观察期间反复收到 `SUCCEEDED`，但 App 始终无法识别并提前结束；如果真机前台超过 60 秒仍没有转为 `Failed`，则还需要另外采集 60 秒后的完整日志和 App 生命周期事件，排查是否存在任务取消或展示层未接收超时更新。该现象不是当前日志能够证明的第二个根因。

## 3. 为什么现有自动化测试没有发现

`Tests/Site/SiteGatewayCloudTimeZoneResponseParserTests.swift` 当前成功样例使用的是 `SUCCEED` 或 `Succeed`，与解析器实现完全一致，但与本次服务器真实响应 `SUCCEEDED` 不一致。

现有 focused parser test 已在当前工作树运行并通过。这只能证明已有约定 `SUCCEED` 能被解析，不能证明真实服务器响应契约已覆盖。这里是测试样例与线上响应发生漂移，而不是状态机已有成功测试失效。

## 4. 其他 targets 的影响范围

源码级结论：四个品牌 target 都存在相同风险。

`SiteEditViewController` 以及以下共享实现都被加入四个 target 的 Sources：

- `SiteGatewayCloudTimeZoneResponseParser.swift`
- `SiteGatewayCloudTimeZoneAPIClient.swift`
- `SiteGatewayCloudTimeZoneSyncCoordinator.swift`
- `SiteGatewayCloudTimeZoneSyncState.swift`
- `SiteTimeZoneEditSyncCoordinator.swift`

对应 target 为：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

四个 target 也共用相同的 Gateway datetime update 和 request status 路径。因此，只要对应区域服务器返回 `SUCCEEDED`，都会走到同一个解析缺陷，并出现成功响应无法结束 `Pushing...` 的问题。

需要区分两类结论：

- 已确认：SLG Sync Plus 的真实日志已经复现；
- 源码推导：其余三个 target 使用相同实现，具备相同缺陷；当前没有它们各自的真实服务器日志，不能声称已经逐一在线复现。

## 5. 最小修复方案

### 5.1 修复响应状态兼容性

修改 `SiteGatewayCloudTimeZoneResponseParser.remoteStatus`：

- 将服务器实际返回的 `SUCCEEDED` 识别为内部成功状态；
- 保留对既有 `SUCCEED` 的兼容，避免影响可能仍返回旧拼写的服务器或区域；
- 保持现有大小写和首尾空白兼容；
- 不扩大接受范围到没有证据支持的 `SUCCESS`、布尔值或数字，继续对未知值 fail closed。

不需要修改内部状态机枚举名称，也不需要修改 API、UI 文案、轮询间隔或超时策略。

### 5.2 增加真实响应回归测试

在 `SiteGatewayCloudTimeZoneResponseParserTests` 中新增与本次日志结构一致的样例，至少验证：

1. `data` 为字典数组；
2. Gateway MAC 为大写；
3. 状态为 `SUCCEEDED`；
4. 解析结果包含归一化 Gateway ID 和内部成功状态；
5. 将解析结果应用到初始 `.pushing` batch 后，该 Gateway 变为 `.synced`，且 batch 可结束。

同时保留现有 `SUCCEED` 用例，明确这是兼容行为，而不是用新拼写替换旧拼写。

### 5.3 保持修复范围聚焦

本次不建议顺手修改：

- Site timezone 的保存与上传顺序；
- Gateway target 构造和权限逻辑；
- request status 的 3 秒轮询间隔；
- 60 秒超时策略；
- `Pushing...`、`Synced`、`Failed` UI 文案与国际化；
- 网络 endpoint、请求 body、AppKey/AppSecret 或 target 配置；
- NordicSigMeshSDK。

## 6. 验证计划

### 6.1 自动化验证

1. 先添加真实 `SUCCEEDED` 用例，并确认旧实现下测试失败；
2. 完成最小 parser 修复后，运行 focused parser test；
3. 运行完整 `scripts/check_site_sync_gateways.sh`；
4. 运行 `git diff --check`；
5. 直接使用 generic iPhoneOS、关闭签名，依次构建四个 target：SunSmart、Archipelago、SLG Sync Plus、SylSmart；构建时不使用 Simulator，也不使用 shell 包装或日志重定向。

### 6.2 真实服务器验收

SLG Sync Plus 至少验证一次：

1. Edit Site 修改 timezone；
2. Site update 返回成功；
3. Gateway datetime update 返回有效 requestId；
4. request status 返回 `SUCCEEDED`；
5. 对应 Gateway 行在该次响应后由 `Pushing...` 变为 `Synced`；
6. 不再为已成功 Gateway 发起后续轮询；
7. 多 Gateway 场景中，成功项先转 `Synced`，未终态项继续轮询，不互相阻塞。

其余三个 target 至少分别验证一次相同服务器链路，或者由服务端确认所有品牌/区域的 request status 枚举契约一致。自动化测试和 iPhoneOS 构建只能证明共享代码兼容，不能替代真实服务器与 Gateway 下发验收。

## 7. 预期修复后行为

当 request status 返回 `EF725643A2B9 = SUCCEEDED` 时：

1. Parser 输出该 Gateway 的成功快照；
2. batch state 将对应 Gateway 从 `.pushing` 更新为 `.synced`；
3. UI 由 `Pushing...` 更新为 `Synced`；
4. 单 Gateway 场景立即满足 `canDismiss`，协调器取消后续轮询并完成 session；
5. 不需要等待 60 秒超时，也不会把服务器已确认成功的 Gateway 错误显示为 `Failed`。

