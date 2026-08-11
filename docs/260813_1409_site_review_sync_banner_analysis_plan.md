# Site 页面 Review sync 提示组件需求分析与开发规划

## 1. 结论

本需求的主流程已经完整，可以进入方案确认，但还需要明确“Server time zone”的数据真值和刷新异常时的保留策略。推荐采用以下统一口径：

- 页面提示组件只表达最近一次成功解析的服务器状态，不直接使用可能尚未上传成功的本地 `site.timezone`。
- 只有权限范围内至少一个 Gateway 的 `timezoneOffset` 与服务器 Site time zone 不一致时，才展示提示组件。
- `Sync status` 仍是每个 `SiteViewController` 实例首次成功响应的进入态弹窗；同一 Site 页面栈内的下拉刷新、网关关联变化刷新等后续请求只更新页面提示组件，不再次显示弹窗。
- 弹窗内的 `LATER` 与 `REVIEW SYNC` 都只关闭弹窗；页面提示组件内的 `Review sync` 才进入空的 `Sync gateways` 页面。
- 后续刷新失败或响应无法形成有效时区快照时，保留上一次已经确认的提示组件状态，不用未知结果覆盖为“无需同步”。

在这个口径下，可以复用当前已经实现的 Site/Space 权限范围、Gateway ID 过滤和 Offset 比较规则，但需要把“只服务首次弹窗的结果”与“可被每次成功响应更新的页面状态”分离。

## 2. 当前源码事实

### 2.1 Site 下拉刷新确实重新获取服务器数据

两个 Space 列表的 `UIRefreshControl` 都调用 `SiteViewController.loadSiteRequest()`，该方法请求 `/sitespace/get/siteprops`，成功后把响应交给 `site.update(siteJsonData:)` 导入。

现有导入不是无条件用 cloud 覆盖 app：只有服务器 `updateTimestamp` 大于本地 `site.lastUpdate` 时，才覆盖 Site name、image、timezone 和版本信息。因此，“cloud.site.timezone 有更新则更新 app.site.timezone”当前成立的前提是服务器同时返回了更新后的、更大的 `updateTimestamp`。这与当前 Site props 的版本模型一致，也能避免覆盖尚未成功上传的本地编辑。

### 2.2 后续刷新当前不会再次显示 Sync status，但也不会重新产出 Gateway 页面状态

`SiteEntryTimeZoneSyncCoordinator` 使用 `hasConsumedEntryResponse` 保证每个 Controller 实例只消费首次响应。首次之后 `prepare` 直接返回 `noAction`，所以当前行为已经避免重复弹窗。

但这也意味着后续响应虽然会继续导入 Site、Space 和 Gateway 数据，却不会通过现有 entry decision 重新输出 Gateway 待同步数量。本次需求必须增加独立的页面展示状态计算，不能解除首次消费限制，否则会让下拉刷新重新触发 `Sync status`。

### 2.3 当前弹窗两个按钮都只关闭弹窗

- `LATER` 调用统一的弹窗完成清理。
- 弹窗 `REVIEW SYNC` 进入独立扩展点，但该扩展点当前同样只执行弹窗完成清理。

这与本次“点击 LATER 或 REVIEW SYNC 后先展示 Site 页面”的要求一致。页面提示组件的按钮需要走另一条导航入口，不能复用弹窗按钮回调后立即跳转。

### 2.4 Site 页面现有布局适合把组件放进 Gateway supplementary header

Site 页面由横向分页的 All Spaces 与 Favourites 两个 Collection View 组成。每个列表顶部复用 `SiteGatewayHeaderView`，当前依次展示：

1. Gateway 选择条，高 40；
2. 上间距 8；
3. Gateway 状态条，高 40；
4. 下间距 8；
5. 第一张 Space Cell。

Figma 新组件正好位于 Gateway 状态条和第一张 Space Cell 之间。把它加入 `SiteGatewayHeaderView`，并让 header 根据可见子组件计算高度，可以同时保证 All Spaces 与 Favourites 一致，且组件与上下内容均保持 8 间距。

## 3. Figma 结构化规格

已读取节点 `399:12189` 与 `399:12229`。目标组件 `Actions/ServerTimeZoneUTC08` 在 375 宽页面中的尺寸为 343 × 56，主要规格如下：

| 项目 | Figma 值 |
| --- | --- |
| 容器 | 高 56，圆角 14，背景 `#FFF9EF` |
| 内边距 | 四周 12 |
| 子项间距 | 12 |
| Warning icon | 16 × 16，颜色 `#E17100` |
| 描述文本 | SF Pro Display Regular，12，行高 16，颜色 `#64748B`，最多两行 |
| 按钮 | 白色背景，高 28，水平内边距 10，垂直内边距 6，圆角 10 |
| 按钮文案 | SF Pro Display Semibold，12，行高 16，颜色 `#973C00` |
| 上下内容间距 | 均为 8 |

现有 `site_entry_sync_warning` 是同尺寸、同路径和同颜色的 16 × 16 SVG，可直接复用，不需要新增图片资源。

Figma 文案是 `Server time zone UTC+08:00 · 3 gateways need time zone sync` 和 `Review sync`。现有弹窗 key 使用全大写 `REVIEW SYNC`，页面按钮应新增独立本地化 key，避免改变弹窗文案。

## 4. 页面状态规则

### 4.1 状态模型

页面只需要两种展示状态：

- hidden：服务器 Site timezone 有效，但权限范围内没有待同步 Gateway；或当前用户为 Visitor，不提供 Gateway 同步操作。
- review：包含服务器实际时区和待同步 Gateway 数量。

页面状态不保存进数据库，生命周期限定在当前 `SiteViewController` 实例。它由最近一次成功解析的服务器响应更新；退出 Site 后重新进入，再按新的首次响应重建。

### 4.2 Gateway 范围沿用已确认权限规则

- Owner：比较响应中的全部 Gateway，按规范化后的 Gateway ID 去重；缺失 ID 的记录按独立 Gateway 处理。
- 至少拥有一个 Editor Space 的非 Owner：只比较 Editor Spaces 的 `gatewayId` 所绑定 Gateway；同 ID 去重；绑定对象缺失或 Offset 非法时按待同步。
- 仅 Visitor Spaces：不比较、不展示组件，因为没有后续同步权限。

### 4.3 比较基准

组件写的是 `Server time zone`，因此 Gateway 必须与服务器实际时区 Offset 比较：

- 普通首次响应、cloud 胜出、Site 时区本来一致：使用响应中的 cloud timezone。
- app timezone 成功更新到 cloud：使用成功写入后的 app timezone，因为它已经成为服务器实际值。
- app timezone 更新 cloud 失败或超时：仍使用进入流程时响应中的 cloud timezone，不能显示失败写入的目标值。
- 后续下拉刷新：直接使用本次成功响应中的 cloud timezone。

现有 entry result 只携带“本次仲裁目标 timezone”，在 app 上传失败时不能代表服务器实际值。因此需要保留首次响应的 remote context，或让共享策略同时产出 server truth 与 operation target，避免页面组件使用错误时区。

### 4.4 刷新矩阵

| 请求结果 | cloud Site timezone | Gateway 对比 | 页面组件 | Sync status |
| --- | --- | --- | --- | --- |
| 成功，remote 版本更新 | 按现有导入规则更新 app | 按 remote timezone 重算 | 按新结果显示或隐藏 | 不显示 |
| 成功，remote 版本未更新 | app Site props 不被强制覆盖 | 仍按 remote timezone 重算 | 按新结果显示或隐藏 | 不显示 |
| 成功，全部 Gateway 一致 | 保持正常导入 | pending = 0 | 隐藏 | 不显示 |
| 成功，存在不一致 | 保持正常导入 | pending > 0 | 展示新数量和 Offset | 不显示 |
| 请求失败 | 不更新 | 无可信新结果 | 保留旧状态 | 不显示 |
| 响应时区非法或关键字段缺失 | 不强制清空有效本地值 | 无可信新结果 | 保留旧状态 | 不显示 |

## 5. 交互与导航

### 5.1 首次进入

1. 获取并解析首次成功响应。
2. 执行现有 Site timezone 仲裁和 Gateway 比较。
3. 如需显示 `Sync status`，继续用现有 Overlay 完成检查和结果展示。
4. 在 Overlay 结果确定后先更新被遮挡的 Site 页面提示状态。
5. 用户点击 `LATER` 或弹窗 `REVIEW SYNC` 后只关闭 Overlay，页面立即呈现已更新的提示组件。

这样既符合“两个弹窗按钮都先回到 Site 页面”，也不会出现弹窗消失后组件再跳动一次。

### 5.2 页面提示按钮

页面组件的 `Review sync` 使用当前 Navigation Controller push 一个新的空白 `SyncGatewaysViewController`：

- Navigation title 为本地化后的 `Sync gateways`。
- 保留现有返回按钮与导航样式。
- 本期不传 Gateway 列表，不做扫描、连接、写入、进度或结果 UI。

### 5.3 两个分页列表

All Spaces 与 Favourites 的 header 都展示同一份 Site 级状态。切换分页不会重新计算，也不会出现一个分页显示、另一个分页不显示的差异。

## 6. 方案比较

### 方案 A：共享纯策略 + Controller 页面状态（推荐）

从现有权限和 Offset 比较中抽出一个无副作用的 Gateway review evaluator。首次 entry policy 和后续页面刷新共同调用它；Controller 只保存当前页面展示状态并驱动两个 header。

优点：比较规则只有一份；首次弹窗和后续刷新生命周期清晰分离；容易覆盖权限、失败上传和刷新矩阵。改动聚焦，不需要持久化临时 UI 状态。

### 方案 B：直接保存上一次 `SiteEntryTimeZoneResult`

弹窗完成时把 result 保存到 Controller，刷新时尝试继续更新 result。

缺点：entry result 的 timezone 是仲裁目标，不一定是服务器实际值；后续刷新不再产生 result；为了修补会把 entry coordinator 变成页面状态容器，职责混杂，不推荐。

### 方案 C：导入后读取本地 Site/GatewayModel 再比较

优点：调用点简单。缺点：本地 GatewayModel 可能因版本判断保留本地较新 Offset，Editor 范围还可能受到本地残留关联影响；不能保证组件反映同一次服务器响应，不推荐。

## 7. 推荐开发拆分

### Task 1：提取可复用的页面 Review 状态策略

涉及：

- `SiteEntryTimeZoneSyncPolicy.swift`，或新建同目录的聚焦 Policy 文件；
- `SiteEntryTimeZoneSyncPolicyTests.swift`。

内容：

- 定义 hidden/review 页面状态；review 包含服务器时区与 pending count。
- 复用 Owner、Editor Spaces、Visitor 权限范围和 Gateway ID 去重规则。
- 支持以明确的 server timezone 计算 pending，避免使用可能未上传成功的本地目标。
- 测试 Owner、Editor/Visitor 混合、Visitor、重复 Gateway、缺失对象、非法 Offset、0/1/N pending。

### Task 2：让首次结果和后续刷新共同更新页面状态

涉及：

- `SiteViewController.swift`；
- `SiteEntryTimeZoneSyncCoordinator.swift` 或结果上下文模型；
- Coordinator 与 Controller contract tests。

内容：

- 保留 `hasConsumedEntryResponse`，禁止后续刷新再次显示 Overlay。
- 首次 Overlay 结果完成时，根据成功或失败后的服务器实际时区更新页面状态，再展示结果按钮。
- 每次后续成功响应都重新计算页面状态；请求失败或解析失败时保留旧状态。
- remote timestamp 更新时继续由现有 `site.update` 更新 app Site timezone，不额外建立第二套持久化路径。

### Task 3：实现 Figma Review sync 组件并接入双 header

涉及：

- 新建 `SiteTimeZoneReviewSyncView.swift`；
- 修改 `SiteGatewayHeaderView.swift`；
- 修改 `SiteViewController.swift`；
- UI contract tests。

内容：

- 按 Figma 实现 56 高、14 圆角、颜色、字体、两行描述和 28 高按钮。
- 复用 `site_entry_sync_warning` 资源。
- header 根据 Gateway list、Gateway status、Review sync 三者可见性统一排版；相邻可见块间隔及 header 底部间隔均为 8。
- 页面状态变化后刷新两个 collection header，并使布局高度同步变化。

### Task 4：增加空的 Sync gateways 页面和导航

涉及：

- 新建 `SyncGatewaysViewController.swift`；
- 修改 `SiteViewController.swift`；
- 修改 `SunSmart.xcodeproj/project.pbxproj`；
- Navigation contract tests。

内容：

- 页面仅提供本地化标题、项目通用背景和返回能力。
- 只有页面组件按钮 push；弹窗 `REVIEW SYNC` 继续 dismiss-only。
- 新文件加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 target。

### Task 5：国际化与回归验证

涉及：

- `SunSmart/en.lproj/Localizable.strings`；
- `SunSmart/zh-Hans.lproj/Localizable.strings`；
- 相关 localization/UI contract tests。

新增文案：

- Server time zone + Offset + Gateway 数量组合描述；英文需分别处理 1 gateway 与 N gateways。
- 页面按钮 `Review sync`。
- 页面标题 `Sync gateways`。

验证顺序：

1. 纯 Policy 与 Coordinator 测试；
2. Site entry、Site props、UI、navigation contract tests；
3. English 与简体中文 strings 语法检查；
4. `git diff --check`；
5. 直接使用 generic iPhoneOS 构建 SunSmart、Archipelago、SLG Sync Plus、SylSmart，不使用 Simulator。

## 8. 验收场景

- 首次进入，Site 发生更新但 Gateway 全部一致：沿用现有只含 `GOT IT` 的 Overlay，关闭后无页面组件。
- 首次进入，Site 与 Gateway 原本都正常：沿用现有直接进入 Site 的行为，不属于本期改动。
- 首次进入，有 3 个 Gateway 不一致：Overlay 的 `LATER` 与 `REVIEW SYNC` 均关闭并回到 Site；页面显示服务器 Offset 和 3 个 Gateway。
- 首次 app timezone 更新 cloud 成功：组件使用更新成功后的服务器 Offset。
- 首次 app timezone 更新 cloud 失败：组件使用原服务器 Offset，不能把失败目标写成 `Server time zone`。
- 下拉刷新后 cloud timezone 更新且 2 个 Gateway 不一致：app timezone 按版本规则更新，组件更新为新 Offset 和 2。
- 下拉刷新后全部 Gateway 一致：组件消失，Space Cell 上移，保持 8 间距。
- 下拉刷新失败或返回非法 timezone：不重复弹窗，保留旧组件。
- Owner、混合 Editor/Visitor、纯 Visitor 分别遵守已确认的 Gateway 权限范围。
- All Spaces 与 Favourites 切换前后组件状态一致。
- 点击页面 `Review sync` 进入空的 `Sync gateways` 页面；返回后 Site 状态保持。

## 9. 不在本期范围

- 不实现 Gateway 扫描、连接、选择、逐台同步、重试、进度和结果页。
- 不发送 BLE/Mesh Time Set 或 Time Zone Set。
- 不修改 Gateway `timezoneOffset`。
- 不在 `Sync gateways` 返回时自动刷新；后续真实同步功能落地时再定义。
- 不把页面临时提示状态持久化到数据库。
- 不改变 `GOT IT` 正常结果流程。

## 10. 需要确认的口径

推荐确认以下两点后再写正式实施计划并编码：

1. `Server time zone` 采用最近一次成功获取或成功写入的服务器实际值；上传失败时继续显示原 cloud timezone。
2. 下拉刷新失败或响应非法时保留旧组件，只有新的合法服务器快照证明全部 Gateway 已同步时才隐藏。

如果以上两点确认，推荐按方案 A 实施。
