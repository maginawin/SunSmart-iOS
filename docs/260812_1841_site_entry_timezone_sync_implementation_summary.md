# Site 入口时区同步实施总结

## 实施结果

已按确认方案完成 Site 页面首次成功获取 `sitespace/get/siteprops` 后的 Site 级别时区仲裁与提示流程。本阶段不执行任何 Gateway 写入、BLE/Mesh 操作或 Gateway 级同步。

## 核心规则

- 每个 `SiteViewController` 生命周期内，仅消费第一次成功响应；刷新不会重复触发。
- 仅当当前成功响应中的用户角色为 Owner 或 Editor 时参与仲裁；其他角色维持现状。
- 本地与服务器时区相同，维持现状。
- 服务器 `updated` 严格晚于本地时间戳时，采用服务器时区并写入本地，不回传服务器。
- 服务器时间戳不严格更新时，采用本地时区，并以新的单调递增时间戳提交服务器。
- 无效时区标识、缺失必要字段或请求失败均维持现状。
- 采用本地时区提交失败或超时后保留待同步状态；超时后的迟到成功不会误清除待同步状态。

## UI 与交互

- 时区不一致并进入同步流程时，展示专用遮罩弹窗 `Checking sync status...`。
- 首屏至少展示 1 秒；流程最长等待 30 秒。
- 完成或超时后切换结果视图，当前阶段统一显示 `All gateways are in sync`。
- 仅点击 `GOT IT` 后关闭弹窗。
- 弹窗期间禁用返回按钮和侧滑返回；关闭后恢复进入弹窗前的手势状态。
- 若入口还有自动跳转逻辑，则延迟到用户点击 `GOT IT` 后执行。
- 新增英文与简体中文本地化，并加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 target。

## Gateway 范围说明

- 当前仅使用 Gateway 数量选择结果文案；没有 Gateway 时显示 `No gateways to sync`。
- 现有 Gateway 且正式同步状态字段尚未定义时，按已确认要求显示 `All gateways are in sync`。
- Gateway 级同步及正式状态字段解析留待后续独立功能实现。

## Figma 弹窗对齐补充

2026-08-12 已依据 Figma 节点 `399:11418` 与 `399:11390` 重新实现 `SiteEntryTimeZoneSyncOverlay`：

- 检查态调整为 302 × 188 pt、20 pt 圆角，并对齐 Loading、标题、描述的尺寸和间距。
- 结果态调整为 343 × 296 pt、24 pt 圆角，状态内容宽度为 313 pt。
- 两张状态卡调整为 64 pt 高、16 pt 圆角、`#F6F8FF` 背景，并加入 Figma 成功图标。
- `GOT IT` 调整为底部 60 pt 透明文字按钮和黑色 3% 分隔线。
- Loading 与成功图标均使用 Figma 导出的原始 SVG，放入共用 Asset Catalog。
- 英文 Site/Gateway 标题大小写已与 Figma 文案一致。

对应设计与实施计划：

- `docs/260812_1901_site_entry_sync_overlay_figma_alignment_design.md`
- `docs/260812_1901_site_entry_sync_overlay_figma_alignment_plan.md`

## 验证结果

已通过以下聚焦测试：

- `SiteEntryTimeZoneSyncPolicyTests`
- `SiteEntryTimeZoneSyncCoordinatorTests`
- `SiteEntryTimeZoneSyncContractTests`
- `SitePropsEditPolicyTests`
- `SitePropsAPIContractTests`
- `SiteTimeZonePersistenceContractTests`
- `SiteTimeZoneUIContractTests` 路由检查
- `SiteTimeZoneUIContractTests` 本地化与 target membership 检查

以下四个 target 均已使用 generic iOS device、Debug、禁用签名完成构建验证：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

构建中仍可见工程原有的资源重复、FSCalendar 和 Info.plist 等警告，本次改动未引入新的编译错误。

Figma 对齐改动完成后，以上聚焦测试和四个 target 均已在最终源码树上重新验证；新增 Asset Catalog JSON 与 SVG 也已分别通过 `jq`、`xmllint` 和构建阶段 `actool` 校验。

## 仍需真实环境验收

- 对照 Figma 检查不同尺寸、iPad、Dynamic Type、加载动画和遮罩视觉效果。
- 验证 1 秒最短展示、30 秒超时、返回/侧滑拦截以及 `GOT IT` 后恢复。
- 使用真实 Owner、Editor、Visitor 响应验证权限分支。
- 使用真实服务器验证提交成功、失败、超时及迟到响应。
- 后续 Gateway 功能开发时确认正式同步状态字段及语义。

以上静态测试和构建结果不能替代真实服务器、真机及 Gateway 端到端验收。
