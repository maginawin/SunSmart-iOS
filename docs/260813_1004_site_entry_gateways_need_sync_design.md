# Site 入口 Gateway 待同步状态设计

## 目标

为 `SiteEntryTimeZoneSyncOverlay` 增加 `gatewaysNeedSync` 状态，并对齐 Figma 节点 `399:11362`。当 Site 时区处理完成、但仍有 Gateway 需要同步时，弹窗提供 `LATER` 与 `REVIEW SYNC` 两个出口；本次只暴露 Review 回调，不实现后续同步业务。

## 状态与数据

- `State` 新增 `gatewaysNeedSync(SiteEntryTimeZoneResult)`，关联结果用于显示 Site UTC offset、Site 同步结果及待同步 Gateway 数量。
- 保留现有 `checking` 与 `result` 状态语义。
- `showResult(_:)` 继续作为 Controller 的统一展示入口：当 `result.gateway` 为 `.pending` 时切换到 `gatewaysNeedSync`，其他 Gateway 结果仍进入普通 `result`。
- Overlay 只负责根据结果选择展示状态，不改变 `SiteEntryTimeZoneSyncCoordinator`、时区仲裁、超时或 Gateway 同步业务。

## UI

- 复用现有 343 × 296 pt、24 pt 圆角结果卡、标题和两张 313 × 64 pt 状态卡。
- Site 行继续按实际结果展示动态 UTC offset、成功或失败状态。
- `gatewaysNeedSync` 的 Gateway 行使用 Figma 橙色警告样式：文字 `#E17100`、图标底色为该颜色 10% 透明度、16 × 16 pt 警告图标。
- 警告图标使用 Figma 导出的原始 SVG，加入共用 Asset Catalog，供四个品牌 target 共同使用。
- 底部保持 60 pt 高度，顶部保留横向分隔线，新增中间竖向分隔线。
- 左按钮文案为 `LATER`，颜色 `#404F66`；右按钮文案为 `REVIEW SYNC`，颜色 `#6667AB`。两项文案均新增 English 与简体中文国际化 Key。
- 普通 `result` 仍只显示现有 `GOT IT`，不改变既有视觉和行为。

## 交互与 Controller 回调

- Overlay 新增 `onLater` 与 `onReviewSync` 回调。
- `LATER` 点击后由 `SiteViewController` 执行现有完成流程：取消任务、关闭 Overlay、解除返回锁定并继续入口后的既有导航。
- `REVIEW SYNC` 点击后同样先完成上述关闭流程，并通过独立 Controller 回调入口保留后续业务扩展点；本次不导航到同步页面、不发送 Gateway、BLE 或 Mesh 指令。
- 两个按钮仅在 `gatewaysNeedSync` 状态响应；`GOT IT` 仅在普通 `result` 状态响应；`checking` 仍不可关闭。

## 测试与验证

- 先扩充 `SiteEntryTimeZoneSyncContractTests`，覆盖新状态、自动状态选择、双按钮、警告资源、国际化 Key、回调和 Controller 关闭路径，并确认旧实现按预期失败。
- 以最小实现使新增契约通过，再回归 Site 入口时区同步的 Policy、Coordinator、Contract 测试。
- 运行 `git diff --check`。
- 按项目构建规则，使用 generic iPhoneOS 和 `CODE_SIGNING_ALLOWED=NO` 验证 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target。
- 静态契约与构建不能代替真机视觉、点击、动画和后续 Review 业务验收；这些边界在交付总结中单独注明。

## 范围边界

- 不修改同步协调器、服务器接口或 Gateway 同步策略。
- 不实现 `REVIEW SYNC` 后续页面或业务。
- 不改变 `checking`、普通 `result`、`GOT IT`、入口导航锁定和超时处理。
- 不重构无关模块，不修改 target 专属资源或依赖。
