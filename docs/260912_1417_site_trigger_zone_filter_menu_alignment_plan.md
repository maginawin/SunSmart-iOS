# Site Trigger Zone 筛选菜单宽度与位置对齐方案

日期：2026-09-12。状态：用户已确认实施，并补充“左侧展开的 space 列表中行高也改成 30”。下文方案按确认结果更新；差异表保留修改前的状态。

## 结论与需求理解

优化合理可行。目标是选中 Site Trigger Zone item 后，在添加面板点击 `New only` 或 `Used` 控件弹出的两项筛选菜单，与 Site → Space → More → Trigger Zone → `Add to Zone X` 中的筛选菜单采用相同尺寸与相对定位规则。

“位置一致”建议定义为相对于各自筛选控件的右边和底边一致，不采用屏幕绝对坐标；两处面板实际高度可能不同，复制绝对坐标会使菜单脱离触发控件。

## 源码依据与差异

两个入口共用 `GroupPathSequenceDeviceAddView` 和 Quick add、Trigger add、Manually add 三种子视图。三种子视图的 `addTypeSelectAction` 在 Site 浏览配置存在时，统一提前转入 `GroupPathSequenceBrowseConfiguration.showFilter`。

| 项目 | Space Trigger Zone | Site Trigger Zone 当前实现 |
| --- | --- | --- |
| iPhone 菜单宽度 | 256pt | 首选 320pt，受窗口安全区宽度限制 |
| iPad 菜单宽度 | 320pt | 首选 320pt，受窗口安全区宽度限制 |
| 水平位置 | 菜单右边与筛选控件右边对齐 | 优先右对齐，越界时向安全区内平移 |
| 垂直位置 | 固定在控件底部下方 4pt | 根据上下空间选择向下或向上，间隔 4pt |
| 行高／两项总高度 | 30pt／60pt | 44pt／正常情况下 88pt |
| 展示宿主 | 全局 keyWindow | 控件实际所属 UIWindow |

Site 与 Space 已使用相同的菜单组件、12pt 字体、白底、边框、圆角和选中高亮风格。`SubText_Color` 与 Space 使用的 RGB(100, 116, 139) 相同，`Border_Color` 与 RGB(236, 236, 236) 相同，无需重做样式。

主要证据：

- [Site 菜单配置](../SunSmart/Main/Group/Path/View/GroupPathSequenceBrowseConfiguration.swift)
- [Quick add 菜单及控件约束](../SunSmart/Main/Group/Path/View/GroupPathSequenceQuickAddView.swift)
- [Trigger add 菜单及控件约束](../SunSmart/Main/Group/Path/View/GroupPathSequenceTriggerAddView.swift)
- [Manually add 菜单及控件约束](../SunSmart/Main/Group/Path/View/GroupPathSequenceManuallyAddView.swift)
- [Space 模式配置入口](../SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift)
- [通用菜单约束](../SunSmart/Common/View/TitleSelectView.swift)

## 建议开发方案

1. 在 `GroupPathSequenceBrowseConfiguration` 中为右侧筛选菜单设置独立布局参数：iPhone 256pt，iPad 320pt；正常情况下菜单右边等于控件右边，顶部等于控件底部加 4pt。移除该筛选菜单的自动向上展开行为。
2. 右侧筛选菜单行高对齐到 Space 的 30pt，两项总高 60pt；按用户补充要求，左侧 Space 列表行高也统一为 30pt。
3. 保留控件所属 UIWindow 与实时坐标转换，布局完成后计算锚点。普通尺寸严格右对齐；仅在窄窗口导致菜单越过安全区时缩窄或水平回移。保持下方展开，极端情况下下方空间不足时限高滚动，连一行都放不下时不展示；实现时将现有 44pt 最低高度判断改为使用该菜单实际行高。
4. 左侧 Space 菜单保留控件等宽、左对齐、下方 4pt 与限高滚动，行高改为 30pt，列表总高度和最低可展示高度随之调整。两种菜单共用 30pt 行高，分别配置水平定位策略。
5. 三种添加模式自动复用本次调整，预计无需修改三个子视图、通用 `TitleSelectView` 或 Space 入口。保留当前菜单文案、选中高亮、关闭行为、筛选回调和候选业务规则。

控件自身宽度不等于弹出菜单宽度：本轮调整弹出的两项菜单，保留 Site 当前筛选控件宽度策略及其右侧 12pt 布局约束。面板高度、帮助页、候选读取、SDK、Mesh 连接、成员保存、本地化资源及 target 配置均不属于本次开发范围。

现有工作树已有上一轮未提交的 UI 改动。本轮以当前工作树为基线，在上述配置文件增量修改，保留既有成果。

## 验证与验收

预计主要修改一个生产配置文件，按需扩展现有 `Tests/UI/SiteTriggerZoneCandidateLayoutProbe.swift`。测试应实际调用生产菜单并测量 UIKit 布局结果，不能仅断言常量或源码字符串。

- Quick add、Trigger add、Manually add 在 `New only`、`Used` 两种状态下，菜单宽度、右边和下方 4pt 间隔符合方案。
- 在同一宿主条件下对比 Site 与 Space 菜单，正常尺寸几何值一致；若确认行高同步，则两项总高均为 60pt。
- 英文、简体中文，窄屏 iPhone、常规 iPhone、iPad，检查文字显示、边缘保护和不同面板高度；单纯改变容器宽度不算验证 iPad 的设备分支。
- 切换筛选值、关闭后重开、切换添加模式，检查高亮、回调与状态保持；左侧 Space 菜单保持等宽，验证新的 30pt 行高、列表总高及滚动行为。
- 运行适用的现有 Site Trigger Zone 检查和 `git diff --check`；使用直接 `xcodebuild`、Debug、iphoneos、generic/platform=iOS、关闭签名验证共享品牌 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux。

方案阶段未运行构建或实际 UI 测试。实施时遵循项目规则，不使用 Simulator，默认不由 Codex 运行真机测试；实际界面由用户按清单运行验收，或用户另行明确要求真机自测后执行。仅构建通过不能标记实际布局验收完成。

## 确认记录

用户已确认：三种模式右侧菜单统一使用 iPhone 256pt／iPad 320pt、右对齐、固定下方 4pt，并采用 Space 的 30pt 行高；保留窄窗口边界保护。用户补充：左侧 Space 列表行高也改为 30pt。
