# Time zone sync status 展示优化设计

## 文档状态

- 日期：2026-08-16
- 状态：方案 A 已确认，包含 2026-08-16 补充的网关行状态图标规则
- 工程：SunSmart iOS UIKit
- 设计参考：Figma `One-SunSmart`，节点 `399:11852`
- 范围：进入 Site 后展示的 `SiteEntryTimeZoneSyncOverlay` 结果弹层与网关状态行

## 目标

1. 结果弹层与承载它的当前 ViewController 容器同宽，取消外层左右间隔。
2. 底部 safe area 使用白色背景，但不改变 `DONE` 按钮的位置、Footer 高度或出现时机。
3. 网关行只在左侧展示一个状态图标，右侧只展示状态文字。
4. `Pushing…` 的加载图标移动到左侧后继续保留旋转动画。
5. 保留现有 Dynamic Type、VoiceOver、列表滚动、终态判断和导航锁行为。

## Figma 与当前实现差异

Figma 的 375pt 画板中，外层结果弹层宽度为 375pt；内部 Site 和 Gateway 卡片宽度为 343pt，即左右各保留 16pt 内容间距。底部 Home Indicator 区域为白色。

当前实现把 `resultCardView` 固定为 343pt，并限制在 safe area 左右各至少 8pt，因此外层弹层本身出现左右间隔。它的底边停在 `safeArea.bottom`，safe area 以下仍显示半透明遮罩。网关行则把网关图标固定在左侧，把 loading/success 图标放在状态文字左侧，形成两个图标。

## 已确认方案 A

### 外层弹层宽度

- `resultCardView` 左右边直接约束到 Overlay。
- 删除固定 343pt 宽度、水平居中和 safe-area 左右最小间距约束。
- 内部 `siteStatusCardView` 与 `gatewayStatusView` 继续保留既有 15pt 内边距，因此内容宽度与 Figma 的 343pt 设计保持一致。
- Overlay 仍由 `SiteViewController` 添加到当前导航容器并覆盖其边界，不改变展示宿主或导航栏覆盖行为。

### 底部 safe area

- `resultCardView.bottom` 继续等于 `safeAreaLayoutGuide.bottom`。
- 新增独立白色背景 View，覆盖 `safeAreaLayoutGuide.bottom` 到 Overlay 底部的区域。
- 白色背景只在结果态显示，checking 态继续保持当前遮罩效果。
- 背景 View 位于结果卡片和阴影之后，不参与内容高度计算和触摸处理。

这样可以保持 Footer 与 `DONE` 按钮的原位置，同时让屏幕最底部连续呈现白色。

### 网关行状态矩阵

| 状态 | 左侧图标 | 左侧动画 | 右侧内容 |
| --- | --- | --- | --- |
| `Pushing…` | `site_entry_sync_loading` | 保留旋转动画 | 仅 `Pushing…` |
| `Synced` | `site_entry_sync_success` | 无 | 仅 `Synced` |
| `Failed` | `gateway_sync_tz_fail` | 无 | 仅 `Failed` |

- 删除网关 Cell 内右侧 `statusImageView` 组件及相关约束。
- 加载动画改为添加到左侧 `gatewayImageView.layer`。
- 状态切换、Cell 复用和高度测量前继续先移除加载动画，避免动画残留到终态。
- 左侧图标保持 16pt 视觉尺寸；右侧状态标签的颜色、本地化、Dynamic Type 和压缩优先级保持不变。
- VoiceOver 继续通过 Cell 的 `accessibilityLabel` 与 `accessibilityValue` 朗读网关名称和状态，图片保持装饰性。

## 不在范围内

- 不修改 Gateway 云同步状态机、API、轮询、超时或终态规则。
- 不修改 Site timezone 同步结果映射。
- 不新增或修改用户可见文案、本地化 Key、资源文件、target 配置或依赖。
- 不调整 `DONE` 的显隐条件、点击逻辑、Footer 高度或底部位置。
- 不修改独立的 `SiteTimeZoneSyncStatusView` 编辑 Site 结果页。

## 验证标准

- 新增契约先在旧实现上按预期失败，分别覆盖全宽/safe-area 背景和三种网关图标状态。
- 两个 focused UI contract tests 通过。
- `scripts/check_site_sync_gateways.sh` 全量通过。
- `git diff --check` 通过。
- 使用 generic iPhoneOS、关闭签名运行 `SunSmart` 构建；共享 target 的编译影响根据工程 Sources membership 检查，并在必要时扩展到其他品牌 scheme。
- 自动化结果不替代真机视觉验收；仍需在带 Home Indicator 的设备上确认全宽、底部白色和 `DONE` 位置。

