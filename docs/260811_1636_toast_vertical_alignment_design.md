# Toast 文字与图标垂直对齐修复设计

## 1. 目标

修复 `ToastStatusView` 成功态和失败态中，文字与图标视觉中心未垂直对齐的问题。检查 Standard 与 Site Update 两种外观，修复所有实际存在的错位，同时保持现有尺寸、字体、图标、间距、文案、位置、动画及展示时长不变。

## 2. 根因

- Standard 成功/失败 PNG 的透明像素边界左右、上下对称。
- Site Update 成功/失败 SVG 的 viewBox 与有效图形边界同样居中。
- 当前两种外观都使用水平 StackView 且配置了 `.center`，图标视图的几何中心没有资源侧偏移。
- Site Update 文字同时强制 22 pt paragraph line height；15 pt 系统字体的自然行高小于 22 pt，UILabel 的字形基线因此不能稳定落在行盒视觉中心。这是当前明确存在的偏移来源。
- Standard 使用字体自然行高，没有同类强制行高问题，但需由契约继续保证图标和文字采用共同中心布局。

## 3. 方案

采用已确认的方案 A：显式共同垂直中心，不使用固定视觉偏移量。

### 3.1 Site Update

- 保留 30 × 30 pt 图标容器和 16 × 16 pt 图标。
- 保留 22 pt 文字布局区域和 15 pt Light 字体。
- 不再通过 paragraph style 强制字形行高；改为 UILabel 使用字体自然高度，在 22 pt 文字区域内垂直居中绘制。
- 图标与文字区域继续位于同一水平内容行，并共享垂直中心。

### 3.2 Standard

- 保留现有 14 pt 图标、13 pt Medium 文字、最多两行、动态高度及 10 pt 间距。
- 保留字体自然行高，不引入 baseline offset。
- 契约明确检查水平 StackView 的 `.center` 对齐，防止后续改成 baseline/fill 导致成功、失败图标再次错位。

## 4. 不采用的方案

- 不增加固定的 `±1/2 pt` transform 或 baseline offset：此类魔法值会随字体、语言及系统字体度量变化。
- 不修改 PNG/SVG 留白：现有资源边界已对称，修改资源会掩盖布局问题并偏离 Figma 原始资源。
- 不重构 Toast 展示 API 或动画：与本次问题无关。

## 5. 测试与验证

1. 先扩展 `SiteUpdateToastUIContractTests`：要求 Site Update 使用显式 22 pt 文字区域、自然字体绘制和 `.center` 对齐，并禁止 paragraph style 强制行高。
2. 运行测试确认在当前实现上因仍存在 `minimumLineHeight`/`maximumLineHeight` 而失败。
3. 做最小生产代码修改并确认 focused contract 转绿。
4. 回归 Site Update component/routing、Time Zone UI 相关 contracts。
5. 运行 `git diff --check`。
6. 直接使用 generic iPhoneOS 构建 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 target。

自动契约和构建只能证明源码约束与编译有效，最终视觉中心仍需在真机上对成功、失败以及中英文文案进行确认。

## 6. 边界

- 不修改 Site 更新成功/失败判定与返回 Sites 的时序。
- 失败文案继续为 `Failed to update site.`。
- 不修改本地化、Asset Catalog、target 配置或依赖。
- 不执行 Git commit、push 或 merge。
