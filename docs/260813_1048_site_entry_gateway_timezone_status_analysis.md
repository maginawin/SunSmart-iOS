# Site 入口 Site/Gateway Time Zone 权限与状态分析

## 1. 结论

经补充权限要求后，本次流程不能再只使用 `/sitespace/get/siteprops` 顶层 `site.role` 判断 Owner/Editor。应在响应导入本地模型之前，解析 Site role、每个 Space 的 role、Space 绑定的 `gatewayId`、所有 Gateway 的 `macAddress` 与 `timezoneOffset`，形成一次只读权限快照，再执行 Site timezone 仲裁和 Gateway 范围过滤。

推荐权限口径如下：

- Owner：Site 可写；检查响应中的全部 Gateway。
- 至少拥有一个 Editor Space 的非 Owner：Site timezone 可按版本仲裁并尝试更新 cloud；只检查与 Editor Spaces 绑定的 Gateway。
- 仅拥有 Visitor Spaces：Site 只读，cloud 始终胜出；不允许把 App timezone 上传 cloud，也不进入 Gateway 同步范围。
- 同时拥有 Editor 与 Visitor Spaces：按 Editor 用户处理，但 Gateway 范围只包含 Editor Spaces 绑定的 Gateway，不能因另一个 Visitor Space 绑定同一 Site 的其他 Gateway 而扩大权限。

当前实现仍有两个直接缺口：生产入口没有读取真实 `timezoneOffset`；策略在 cloud/app timezone 相同时直接 `.noAction`，无法显示“Site 已同步、Gateway 待同步”。

## 2. 当前源码事实

### 2.1 Site 与 Space 权限不是同一个维度

- `SiteData.permission` 来自 `/get/siteprops` 顶层 `role`。
- 每个 `SpaceData.permission` 来自响应中对应 Space 的 `role`。
- `SiteData.permissionOperates` 当前只有 Owner 具备 Site `.edit`；非 Owner 即使拥有 Editor Space，也只获得恢复设备和固件升级等 Site 聚合能力。
- `SpaceData.canEditing` 还会考虑 Space 是否被删除、是否需要重新验证密码等本地有效性状态。
- 现有 Site 入口时区策略只检查顶层 Site role 为 Owner/Editor，没有按 Editor Spaces 建立 Gateway 范围。

因此，新需求中的“拥有 Editor Spaces”必须从 Space role/权限集合推导，不能仅把顶层 `site.role == editor` 当作完整答案。

### 2.2 Space 与 Gateway 的关联

- `/get/siteprops` 的每个 Space 使用 `gatewayId` 表示所绑定 Gateway。
- Gateway 对象使用 `macAddress` 作为身份，关联信息还可能出现在 `gatewayPreconfigured.associatedSpaces`。
- 当前导入路径已经使用 Space 的 `gatewayId` 建立 `relevanceGatewayId`；非 Owner 导入 Gateway 时，也会过滤到当前可见 Space 所关联的 Gateway。
- 现有 `SiteData.canConfigureGateway` 不能直接用于本次过滤：非 Owner 只要存在任一有效 Editor Space，对于“没有 associatedSpaces 的 Gateway”也可能返回可配置，这与“仅比较 Editor Spaces 已绑定 Gateway”的新规则不一致。

推荐直接使用同一次远端响应中的 `spaces[].role + spaces[].gatewayId` 生成 Editor Gateway ID 集合，再与 `gateways[].macAddress` 匹配。比较必须在 `site.update(siteJsonData:)` 之前完成，避免导入时权限、关联或 timestamp 覆盖请求前状态。

### 2.3 Site timestamp 是全局版本

- `SiteData.lastUpdate` 同时版本化 siteName、imageId、timezone 等 Site props，不是 timezone 专属 timestamp。
- Owner/Editor 本地值胜出时，现有策略会生成一个严格大于 App 与 cloud 当前 timestamp 的新值并提交 `/sitespace/update/siteprops`。
- Visitor 的 `SiteData.needUploadCloud` 已明确禁止上传，但当前整包导入仅在 cloud timestamp 严格大于 App `lastUpdate` 时覆盖本地属性。
- 当前远端落库路径使用 `max(local.lastUpdate, remoteTimestamp)`，适合“较新的 cloud 胜出”，不适合“Visitor 无条件以较旧 cloud 为准”的新要求。

## 3. Site timezone 仲裁规则

### 3.1 Owner

- cloud/app timezone 相同：不更新 Site，不上传 cloud，Site 状态语义为 `Already in sync with server`；只有存在 Gateway 待同步时才需要展示该状态。
- cloud/app timezone 不同且 cloud `updateTimestamp > app.lastUpdate`：cloud 胜出，App 使用 cloud timezone，成功状态为 `Updated from server`。
- cloud/app timezone 不同且 cloud `updateTimestamp <= app.lastUpdate`：App 胜出，生成严格大于两端 timestamp 的新版本并更新 cloud，成功状态为 `Updated to server`。
- App 上传失败或超时：保留 timezone pending，显示 `Failed to update server`。

### 3.2 拥有 Editor Spaces 的非 Owner

- Site timezone 仲裁规则与 Owner 相同。
- App timezone 胜出时使用现有 `/sitespace/update/siteprops` 提交 timezone。
- 当前客户端没有证据证明服务器一定允许“仅拥有 Editor Space 的用户”更新 Site props；该能力需要以服务端权限契约或真实接口响应确认。若服务端拒绝，客户端只能进入 `Failed to update server`，不能把请求发出等同于更新成功。
- Gateway 比较范围严格限定为 Editor Spaces 绑定的 Gateway。

### 3.3 仅拥有 Visitor Spaces

- 不参与“谁的 timestamp 更新谁胜出”的双向仲裁；只要 cloud timezone 有效，cloud 始终是目标。
- 禁止调用 `/sitespace/update/siteprops`，禁止创建 timezone pending，禁止把 App timezone 上传 cloud。
- 即使 `app.lastUpdate > cloud.updateTimestamp`，也不能让 App 值反向覆盖 cloud。
- cloud timezone 无效时不清空 App 的有效 timezone，保持现状并记录为不可仲裁；不能把无效值写入本地。

## 4. Visitor 是否更新 updateTimestamp

### 4.1 推荐结论

需要消除 Visitor 本地版本高于 cloud 的状态，但不能只替换 timezone 后单独回退 `SiteData.lastUpdate`。因为 `lastUpdate` 是完整 Site props 的共享版本，只更新时间戳会让本地 name/imageId 与 cloud 版本号失配。

推荐把 Visitor 处理定义为“cloud Site props 权威收敛”：

- 使用本次完整、合法的 cloud siteName、imageId、timezone 和 `updateTimestamp` 更新 App。
- `app.lastUpdate = cloud.updateTimestamp`。
- `app.lastUploadCloudTimestamp = cloud.updateTimestamp`。
- 清除所有 Site props pending 及其 pending timestamp，因为 Visitor 不具有继续提交这些本地意图的权限。
- 不发任何 cloud 更新请求。

这样才能真实建立“Visitor 本地不应比 cloud 更新”的不变量，也避免用户以后重新获得写权限时，旧的本地高版本或 pending 被错误上传。

### 4.2 若坚持只处理 timezone

若本期严格只允许修改 timezone，则不建议把全局 `lastUpdate` 回退到 cloud timestamp。应只应用 cloud timezone、清除 timezone pending，并在 Visitor 分支中始终忽略本地 timestamp。该做法能保证 timezone 真值，但 `app.lastUpdate` 仍可能大于 cloud，不满足用户提出的版本不变量。

因此推荐采用完整 Site props 权威收敛，并把这项行为作为需要明确确认的范围扩展。

## 5. Gateway 资格范围

### 5.1 Owner

- 候选集合为响应 `site.gateways` 中全部 Gateway，不要求 Gateway 已绑定 Space。
- 以规范化后的 `macAddress` 去重；同一 Gateway 关联多个 Space 只计算一次。
- 没有 Gateway 时结束 Gateway 检查。

### 5.2 Editor Spaces

- 从响应 `site.spaces` 选出 role 为 Editor 的 Spaces。
- 收集这些 Spaces 的非空 `gatewayId`，规范化并去重。
- 只在 `site.gateways` 中查找这些 ID 对应的 Gateway。
- 同一 Gateway 同时绑定多个 Editor Spaces，只计算一次。
- 同一 Gateway 同时绑定 Editor 与 Visitor Space，仍计算一次，因为至少存在一个 Editor Space 授权范围。
- 仅绑定 Visitor Spaces 的 Gateway 不读取、不计数、不展示。
- Editor Space 声明绑定某 Gateway，但响应缺少对应 Gateway 对象时，该 Gateway 按待同步计数；不能因 payload 不完整把它当成已同步。

### 5.3 Visitor Spaces

- 推荐不建立 Gateway 候选集合，不比较 `timezoneOffset`，不显示 `REVIEW SYNC`。
- 原因是 Visitor 没有后续同步权限，展示可操作的 Gateway 待同步入口会造成权限与 UI 语义不一致。

### 5.4 权限或关联字段异常

- 未知 Space role 不提升为 Editor。
- 缺失/空白 `gatewayId` 视为 Space 未提供有效绑定。
- Gateway ID 比较应忽略大小写和首尾空白。
- 非 Owner 不得因为顶层 Gateway 数组存在额外对象而扩大到未授权 Gateway。

## 6. Gateway timezoneOffset 对比

- `timezoneOffset` 是 SIG Mesh 固定偏移编码，转换公式为：UTC Offset 分钟数 = `(timezoneOffset - 64) × 15`。
- 目标值为 Site 仲裁后最终 `SiteTimeZoneValue.offsetMinutes`。
- 只比较 UTC Offset，不比较 IANA identifier。
- Gateway `timezoneOffset` 与目标分钟数相同：该 Gateway 已同步。
- 值不同：该 Gateway 待同步。
- 字段缺失、Bool、非整数、负数、超出 `UInt8` 或无法转换：该 Gateway 按待同步计数。
- Editor Space 已绑定但 Gateway 对象缺失：该 Gateway 按待同步计数。

## 7. Sync status 状态矩阵

| 用户范围 | Site 对比 | 有资格 Gateway | Gateway 结果 | Site 行 | Overlay |
|---|---|---|---|---|---|
| Owner | 相同 | 无或全部一致 | 无 pending | 无需展示 | 正常进入 |
| Owner | 相同 | 有 | 有 pending | `Already in sync with server` | `gatewaysNeedSync` |
| Owner | cloud 较新 | 任意 | 无 pending | `Updated from server` | `result` |
| Owner | cloud 较新 | 任意 | 有 pending | `Updated from server` | `gatewaysNeedSync` |
| Owner | App 较新或同版本冲突 | 任意 | 无 pending | `Updated to server` 或失败 | `result` |
| Owner | App 较新或同版本冲突 | 任意 | 有 pending | `Updated to server` 或失败 | `gatewaysNeedSync` |
| Editor Spaces | 相同 | 仅 Editor 绑定范围 | 无 pending | 无需展示 | 正常进入 |
| Editor Spaces | 相同 | 仅 Editor 绑定范围 | 有 pending | `Already in sync with server` | `gatewaysNeedSync` |
| Editor Spaces | 不同 | 仅 Editor 绑定范围 | 按目标比较 | 与 Owner 相同 | 按 Gateway 结果选择 |
| Visitor Spaces | cloud 有效 | 不检查 | 不适用 | 推荐静默应用 cloud | 不展示 |

这里将“Site 没有网关/Editor Spaces 没有绑定网关，流程结束”解释为结束 Gateway 分支：如果 Site 本身发生了 timezone 更新，仍沿用此前确认的普通 `result`；只有 Site 本身也无需更新时才完全不展示 Overlay。

## 8. 推荐架构方案

### 方案 A：远端权限快照 + 单一纯策略（推荐）

- Parser 在导入前解析完整 Site props、Site role、Space role/gatewayId 和 Gateway identity/timezoneOffset。
- 权限策略先生成 Owner、Editor Spaces 或 Visitor 范围。
- Site 策略按范围选择目标 timezone 和是否允许 cloud 写入。
- Gateway 策略只对授权 Gateway 集合比较最终目标 Offset。
- Coordinator 处理本地持久化、允许的 cloud 更新、最短展示时间和结果发布。

优点：权限、目标和 Gateway 计数来自同一份响应；Visitor 不会误上传；Editor 不会看到未授权 Gateway；可以用纯测试覆盖完整矩阵。

### 方案 B：导入后使用本地 Site/Space/GatewayModel 再判断

优点：可以复用现有模型。缺点：请求前 App Site 版本可能已被导入覆盖；非 Owner Gateway 快照可能不完整；本地残留关联会影响权限范围，不推荐。

### 方案 C：Owner/Editor/Visitor 各写一套 Controller 分支

优点：业务条件直观。缺点：timestamp 仲裁、Offset 转换、异常降级和 UI 状态会重复，后续容易出现三套规则不一致，不推荐。

## 9. 计划修改范围

- `SiteEntryTimeZoneSyncResponseParser.swift`：解析完整 Site props、Space permission scope、Gateway identity 和 `timezoneOffset`。
- `SiteEntryTimeZoneSyncPolicy.swift`：增加权限范围、Visitor cloud-authoritative 决策、Editor Gateway 过滤、Gateway Offset 统计和 `Already in sync` 结果。
- `SiteEntryTimeZoneSyncCoordinator.swift`：区分远端较新、Visitor 权威覆盖、App 上传和只展示 Gateway 状态；Visitor 路径绝不 submit。
- `SiteViewController.swift`：使用新解析接口，仍在完整导入前捕获 App 快照，每个实例只消费首次成功响应。
- `SiteEntryTimeZoneSyncOverlay.swift`：增加 `Already in sync with server` / `已与服务器同步` Site 行，不改变 `LATER`、`REVIEW SYNC` 关闭行为。
- English 与简体中文 Localizable.strings：增加新 Site 状态文案。
- Policy、Coordinator、Contract 测试：覆盖 Owner、混合 Editor/Visitor Spaces、Visitor、重复关联、缺失 Gateway、非法 Offset 和 timestamp 规则。

## 10. 验证边界

- 先以失败测试锁定权限和状态矩阵，再完成最小实现。
- 回归 Site entry、Site props API/持久化、Edit Site、Overlay 和 alert transition 聚焦测试。
- 检查两种本地化语法、`git diff --check`，并直接构建四个 generic iPhoneOS target。
- 必须用真实 `/get/siteprops` 响应确认 Space role、gatewayId、Gateway macAddress/timezoneOffset 的实际字段形态。
- 必须确认 `/sitespace/update/siteprops` 是否允许“拥有 Editor Space、但不是 Site Owner”的用户更新 Site timezone。
- 静态测试和构建不代表真实服务器权限、真机 UI 或 Gateway/BLE/Mesh 端到端验收。

## 11. 本次不做

- 不实现 `REVIEW SYNC` 后续页面或路由。
- 不扫描、连接或写入 Gateway，不发送 BLE/Mesh Time Set。
- 不更新 Gateway `timezoneOffset`。
- 不修改 Gateway 绑定关系或 Space 权限。
- 不重构无关 Site、Space 或 Gateway 模块。

## 12. 待确认

推荐采用方案 A。进入正式设计与实施计划前，还需确认以下统一 UI/Visitor 口径：

- “没有有资格的 Gateway，流程结束”只结束 Gateway 检查；如果 Site timezone 发生更新，仍展示普通 `result`。
- Visitor 使用完整 cloud Site props 与 cloud `updateTimestamp` 权威覆盖本地、清除全部 Site props pending，并静默完成，不展示 Sync status，也不检查 Gateway。
