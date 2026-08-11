# Toast 文字与图标垂直对齐修复总结

## 结论

已按确认的方案 A 修复 Site Update Toast 文字与成功/失败图标的视觉垂直中心错位。Standard Toast 使用自然行高和 StackView `.center`，没有强制行高根因，保持现有布局和视觉参数不变。

## 根因与修复

- Standard PNG 与 Site Update SVG 的有效图形边界均上下对称，问题不来自图标资源。
- Site Update 对 15 pt Light 字体强制设置了 22 pt paragraph line height，字形基线不能稳定落在行盒视觉中心。
- 修复后 UILabel 使用字体自然高度绘制，并保留显式 22 pt 文字区域；该区域与 30 pt 图标容器继续由水平 StackView `.center` 对齐。
- 未增加 transform、baseline offset 或其他视觉魔法值。

## TDD 证据

1. 修改生产代码前，原有 Toast component contract 通过。
2. 新增垂直对齐契约后运行失败，退出码为 133，失败信息为：
   `Site Update Toast must center natural-height text in its 22pt text area without visual offsets`。
3. 完成最小修复后，同一 component contract 通过。

## 自动验证

以下 focused contracts 均通过：

- `SiteUpdateToastUIContractTests` component
- `SiteUpdateToastUIContractTests` routing
- `SiteTimeZoneUIContractTests` full routing
- `SiteTimeZoneUIContractTests` localization/resource membership

`git diff --check` 无输出。

以下 generic iPhoneOS Debug 构建均显示 `BUILD SUCCEEDED`：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

## 变更边界

- 未修改成功/失败图标资源。
- 未修改 Toast API、文案、间距、位置、动画或时长。
- 未修改 Site 更新判定、返回 Sites 时序、Time Zone 流程、本地化或 target 配置。
- 保留工作树中的既有修改与未跟踪文档。
- 未执行 Git commit、push 或 merge。

## 尚需真机确认

自动 source contract 与构建不能替代 UIKit 实际渲染验收，仍需在真机确认：

1. Site Update 成功和失败 Toast 的图文视觉中心。
2. English 与简体中文文案。
3. Dynamic Type 未被工程启用时的当前默认字号表现。
4. Standard Toast 现有成功/失败、多行文案外观没有回归。
