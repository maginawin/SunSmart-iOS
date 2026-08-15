# Gateway 时区同步审查问题修复计划

> **For agentic workers:** REQUIRED SUB-SKILL: 使用 `superpowers:test-driven-development` 逐项实施；如采用代理执行，使用 `superpowers:subagent-driven-development`，每个任务完成后独立复审。

**目标：** 修复重复 Gateway 快照的未知 offset 被误判为已同步、Gateway 状态 UI 不支持辅助功能字号，以及新增检查脚本不可直接执行的问题。

**架构：** Gateway offset 聚合继续保留在纯值 Target Builder 中，但将“可采信的远端 offset”收紧为同一规范化 ID 的全部快照都存在合法 offset 且完全一致。UI 保持当前底部弹层和内部 Gateway 列表滚动结构，通过自动行高、动态卡片测量及显式高度回调支持 Accessibility Dynamic Type，同时继续受 safe area 顶部约束。脚本只修正文件模式，不调整脚本内容或扩大到其他历史脚本。

**技术栈：** Swift 5、UIKit、SnapKit、纯 Swift focused tests、source contract tests、Bash、Xcode generic iPhoneOS build。

## 全局约束

- 不修改 Gateway 云同步 API、3 秒轮询、3 分钟超时、权限过滤、Site 失败阻断 Gateway 下发或 requestId 生命周期。
- 不新增或修改 Auth 信息，不写 Mesh Node，不调用 `savePropertys()`。
- 不新增用户可见文案；English 与简体中文本地化文件原则上不变。
- 保持 `confirmed > local dirty > remote` 的 offset 优先级；本任务只收紧 remote 层的证据完整性。
- 普通字号下尽量保持现有 Figma 尺寸；辅助功能字号允许组件向上增长，但弹层不得越过 `safeArea.top + 16`，Gateway 列表仍可滚动。
- 不修改用户已有的四份未跟踪需求、设计、实施计划及本修复计划文档。
- 四个共享 target 都必须验证：`SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart`。

---

### Task 1：重复 Gateway 快照采用完整一致证据

**文件：**

- 修改：`Tests/Site/SiteGatewayCloudTimeZoneTargetTests.swift`
- 修改：`SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneTarget.swift`

**接口：**

- 保持 `SiteGatewayCloudTimeZoneTargetBuilder.build(...)` 签名不变。
- 保持 `SiteGatewayCloudTimeZoneTarget.effectiveOffsetMinutes` 和 `requiresSync` 语义不变。
- 修改私有 `remoteOffsetsByID(_:)`：仅当同一规范化 Gateway ID 至少有一条记录、每条记录都有合法 offset、且所有 offset 相等时才返回该值；存在 `nil`、非法解析结果或不一致值时返回未知。

- [ ] **Step 1：补充失败测试**

  在 `testOffsetPrecedenceAndUnknownRemoteOffsets()` 或新的独立测试中覆盖以下矩阵：

  1. 重复快照 `[480, 480]`：远端值为 480，`requiresSync == false`。
  2. 重复快照 `[480, nil]`：远端值未知，`requiresSync == true`。
  3. 重复快照 `[480, 0]`：远端值未知，`requiresSync == true`。
  4. 重复快照 `[nil, nil]`：远端值未知，`requiresSync == true`。
  5. 即使远端重复快照冲突，confirmed 或 local dirty 明确为 480 时仍分别覆盖 remote，`requiresSync == false`。

- [ ] **Step 2：运行 Target Builder focused test，确认旧实现 RED**

  Run：按 `scripts/check_site_sync_gateways.sh` 中 `SiteGatewayCloudTimeZoneTargetTests` 的 `swiftc -parse-as-library` 命令编译并执行。

  Expected：`[480, nil]` 场景失败，明确证明当前 `compactMap` 丢失未知证据。

- [ ] **Step 3：最小修改远端 offset 聚合**

  遍历每个 ID 的原始快照数组，不在一致性判断前丢弃 optional。只有“全部非 nil 且去重后恰好一个值”才输出远端 offset；其余情况保持未知，让既有 `effectiveOffset != targetOffsetMinutes` 判定进入同步。

- [ ] **Step 4：运行 Target Builder 与关联状态测试**

  Run：

  - `SiteGatewayCloudTimeZoneTargetTests`
  - `SiteGatewayCloudTimeZoneSyncStateTests`
  - `SiteEntryTimeZoneSyncPolicyTests`
  - `SyncGatewaysContextTests`

  Expected：全部 PASS；Owner/Editor 范围、顺序、MAC 回退及 confirmed/dirty 优先级无回归。

- [ ] **Step 5：独立提交**

  Commit message：`fix: treat incomplete gateway offsets as pending`

---

### Task 2：修正检查脚本执行权限

**文件：**

- 修改模式：`scripts/check_gateway_detail_proxy_ready_state.sh`，`100644` → `100755`

**接口：**

- 脚本内容、参数、输出和检查数量不变。
- 不批量修改其他历史 `scripts/*.sh` 的权限。

- [ ] **Step 1：记录当前失败证据**

  Run：`test -x scripts/check_gateway_detail_proxy_ready_state.sh`

  Expected：退出码 1。

- [ ] **Step 2：仅增加 owner/group/other execute bit**

  Run：`chmod +x scripts/check_gateway_detail_proxy_ready_state.sh`

- [ ] **Step 3：验证模式与直接执行**

  Run：

  - `git diff --summary -- scripts/check_gateway_detail_proxy_ready_state.sh`
  - `test -x scripts/check_gateway_detail_proxy_ready_state.sh`
  - `scripts/check_gateway_detail_proxy_ready_state.sh`

  Expected：Git 显示模式变为 `100755`；可执行检查退出 0；脚本直接运行输出 PASS。

- [ ] **Step 4：独立提交**

  Commit message：`chore: make gateway proxy check executable`

---

### Task 3：Gateway 状态组件完整支持 Accessibility Dynamic Type

**文件：**

- 修改：`Tests/Site/SiteGatewayCloudTimeZoneUIContractTests.swift`
- 修改：`Tests/Site/SiteEntryTimeZoneSyncContractTests.swift`
- 修改：`SunSmart/Main/Site/View/SiteEntryGatewayTimeZoneStatusView.swift`
- 修改：`SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift`

**接口：**

- 删除 `configureDynamicFont` 对 `maximumContentSizeCategory = .large` 的限制。
- `UITableView` 改用 `automaticDimension`，保留 44pt 作为 estimated/minimum visual baseline。
- `SiteEntryGatewayTimeZoneStatusView.preferredHeight` 与 `minimumViewportHeight` 继续作为 Overlay 的高度接口，但改为基于当前字体、表头、最多三条可见行、空状态及失败摘要的实际测量结果。
- 新增 `SiteEntryGatewayTimeZoneStatusView.onPreferredHeightChanged: (() -> Void)?`；内容字号或布局测量变化时通知 Overlay 重新执行 `updateResultSheetLayout(for:)`。

- [ ] **Step 1：先更新 UI contracts，确认旧实现 RED**

  Contract 必须断言：

  1. 不再出现 `maximumContentSizeCategory = .large`。
  2. 表格使用自动行高并保留 44pt estimated baseline。
  3. Gateway cell 的文字约束同时参与顶部和底部布局，不能只依赖 `centerY` 与固定 rowHeight。
  4. Gateway 卡片、空状态和失败摘要使用 minimum baseline，而不是强制固定高度。
  5. 状态组件具备动态测量及 `onPreferredHeightChanged` 通知。
  6. Overlay 以弱引用 closure 消费通知，并仅在当前为 `.result` 时重新计算弹层高度。
  7. safe-area 顶部约束、DONE 显隐和内部 Gateway 滚动约束仍存在。

  Run：单独编译并执行 `SiteGatewayCloudTimeZoneUIContractTests` 与 `SiteEntryTimeZoneSyncContractTests`。

  Expected：旧实现因字号上限、固定行高/卡片高度和缺少高度通知而 RED。

- [ ] **Step 2：让所有 Gateway 状态文案真正缩放**

  保留 `UIFontMetrics` 与 `adjustsFontForContentSizeCategory = true`，删除字号上限。Gateway 名称、状态、表头/数量、空状态标题/说明、失败标题/说明全部使用当前 content-size category 的字体。

- [ ] **Step 3：改造 Gateway 行与表头的垂直约束**

  - 表格设置 `rowHeight = UITableView.automaticDimension`、`estimatedRowHeight = SCRYFrom(44)`。
  - Gateway 名称和状态标签增加可决定 cell 高度的上下 padding 约束；保留横向压缩优先级，让状态完整显示、长名称按既有策略截断。
  - 图标继续固定视觉尺寸并垂直居中，不参与 Dynamic Type 放大。
  - 表头高度使用 `greaterThanOrEqualTo 44`；表头和数量标签用上下 padding 形成实际高度。

- [ ] **Step 4：让空状态与失败摘要自适应内容**

  - 将 152pt 空状态和 96pt 失败摘要从强制等高改为 minimum baseline。
  - 保留空状态说明和失败指导的多行能力，并用完整 top/bottom 约束形成可测量高度。
  - 保留普通字号下的现有间距、圆角、图标尺寸和颜色，不新增文案。

- [ ] **Step 5：实现动态高度测量与 Overlay 回算**

  - 在状态视图完成 `reloadData()` 与布局后，使用独立 sizing cell 测量最多前三行，并使用不受旧精确容器高度污染的表头、空状态和失败摘要 fitting height 计算高度；实测表头与失败摘要高度回绑真实布局约束。
  - `preferredHeight` 的 Gateway 列表部分最多偏好显示前三行；更多行继续内部滚动。`minimumViewportHeight` 只包含不可压缩的动态表头，以及存在失败时的动态失败摘要与间距，从而在小屏/超大字号下优先压缩表格 viewport 而不越过 safe area。
  - 缓存测量值并做等值保护；只有值变化才 `invalidateIntrinsicContentSize()` 并触发 `onPreferredHeightChanged`，避免 `layoutSubviews` 循环。
  - content-size category 或有效宽度变化时重新测量。
  - Overlay 用 `[weak self]` 注册回调；当前 state 为 `.result` 时调用既有 `updateResultSheetLayout(for:)`，保持底部、safe-area top、DONE footer 和终态动画逻辑不变。

- [ ] **Step 6：运行 UI contracts 与 Swift 解析**

  Run：

  - `SiteGatewayCloudTimeZoneUIContractTests`
  - `SiteEntryTimeZoneSyncContractTests`
  - `xcrun swiftc -parse SunSmart/Main/Site/View/SiteEntryGatewayTimeZoneStatusView.swift SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift`

  Expected：全部 PASS，无固定 `.large` 上限或固定 44pt rowHeight 的旧断言。

- [ ] **Step 7：执行人工辅助功能验收矩阵**

  在 English 和简体中文下分别检查 `.large`、Accessibility Large、Accessibility Extra Extra Extra Large：

  - No gateways。
  - 1 个 Pushing Gateway。
  - 3 个混合状态 Gateway，包含长 Gateway name。
  - 至少 1 个 Failed Gateway 与失败摘要。
  - 全部终态并显示 DONE。

  每个场景确认：文字确实放大、无垂直裁切/重叠、状态仍可辨认、列表可滚动、DONE 规则不变、弹层顶部保留 safe-area 间隔、VoiceOver 仍按 Gateway name + status 朗读。该步骤是 UIKit/视觉证据，不能由 source contract 或 build 代替。

- [ ] **Step 8：独立提交**

  Commit message：`fix: support accessibility sizes in gateway status`

---

### Task 4：组合回归、四 target 构建与最终复审

**文件：**

- 不新增生产文件。
- 如验证结果需要记录，只更新本计划的 checkbox/结果，不改用户原有四份文档。

- [ ] **Step 1：运行完整 Gateway 时区 focused suite**

  Run：`./scripts/check_site_sync_gateways.sh`

  Expected：所有行为测试与 contracts PASS，并输出 `SiteSyncGateways checks passed`。

- [ ] **Step 2：再次直接运行 Proxy Ready 检查脚本**

  Run：`scripts/check_gateway_detail_proxy_ready_state.sh`

  Expected：退出 0 并输出 PASS，证明执行位与脚本行为同时成立。

- [ ] **Step 3：检查模式、语法与 diff**

  Run：

  - `git diff --summary`
  - `git diff --check`
  - 对本次修改的 Swift 文件执行 `xcrun swiftc -parse`
  - `git status --short`

  Expected：只有计划内源码、测试和脚本 mode 变化；四份未跟踪文档保持未加入 Git。

- [ ] **Step 4：串行运行四个 generic iPhoneOS unsigned build**

  按项目规则直接执行 `xcodebuild`，不使用 shell 包装、日志重定向或 Simulator：

  - `SunSmart`
  - `Archipelago`
  - `SLG Sync Plus`
  - `SylSmart`

  Configuration：Debug；SDK：iphoneos；destination：`generic/platform=iOS`；`CODE_SIGNING_ALLOWED=NO`。

  Expected：四个 scheme 均 `BUILD SUCCEEDED`。

- [ ] **Step 5：独立 whole-diff 复审**

  复审重点：重复快照完整证据、confirmed/dirty 优先级、普通字号 Figma 基线、Accessibility category 高度回算、safe-area 上限、DONE/滚动行为、四 target 接线，以及脚本 mode 是否是唯一范围外变化。

  Expected：无 Critical/Important；Minor 明确记录，不把静态 contracts、generic build 或人工视觉检查互相替代。

## 自检结果

- 三条 review comment 均有独立任务、RED 证据、最小实现和对应验证。
- 未引入 API、本地化、Auth、Mesh、数据库或 requestId 变更。
- Dynamic Type 计划同时处理字体、行高、卡片高度和 Overlay 回算，没有停留在删除字号上限。
- 脚本权限修复限定为被审查文件，没有顺手统一历史脚本。
- 真机视觉、VoiceOver、真实服务器和 Gateway 设备行为仍明确属于外部验收边界。

## 实施与验证结果

- 最终 HEAD：`6fe2ba74`；修复提交范围：`bb071eea..6fe2ba74`，未 push、未 merge。
- 重复 Gateway 快照仅在全部 offset 存在且一致时才视为可信；`[480, nil]`、`[nil, 480]`、非法值及不一致值均保持待同步。
- Gateway 状态列表已支持 Accessibility Dynamic Type、自动行高、前三行独立 sizing cell 测量，并将 header/failure 实测高度回绑真实布局约束。
- `scripts/check_gateway_detail_proxy_ready_state.sh` 已为 `100755`，可直接执行。
- 最终 HEAD 上完整 focused suite、Proxy Ready 脚本、Swift parse、`git diff --check` 均通过；SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 generic iPhoneOS unsigned build 均 `BUILD SUCCEEDED`。
- 最终 scoped review 为 0 Critical、0 Important。极端 `available < minimum` 的低高度 safe-area 裁切保留为 deferred Minor，需要整体 sheet 滚动或产品降级决策。
- 未执行真机 Dynamic Type、VoiceOver、真实服务器或 Gateway/BLE Mesh 验收，不能由 source contract 或 generic build 替代。
