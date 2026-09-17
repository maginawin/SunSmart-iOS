# Site Trigger Zone 选中项添加弹窗优化：分析与开发方案

日期：2026-09-12。工作树：`site-tz-plus`。源码基线：`4ec8c508`。

本文最初记录需求分析与开发规划。用户已确认实施，并明确调整：**不补充 Site 上下文，三种模式直接复用现有帮助页及文案**。本文已按确认结果更新；后续实施与验证结果另行记录，历史测试成绩不作为本次验证结果。

## 结论

三项优化合理可行，属于同一添加面板的交互一致性和布局修正，适合集中在一个开发 session 内处理。

- Space 选择器左侧问号可以进入 Space Trigger Zone 使用的同一个帮助页面，并按当前 Quick add、Trigger add、Manually add 分类展示。
- Space 选项列表可以固定在选择器下方，左右边缘与选择器对齐；长列表通过限高滚动容纳。
- Quick add、Trigger add 可以恢复 Proximity Lighting 检测范围提示。已确认 Space 版本的 Manually add 没有这条提示，Site 同样无需增加。

恢复提示时须把提示与现有无权限、加载失败、未连接等状态文案分开布局。帮助页按用户确认直接复用原文，不增加 Site 专用说明。

## 源码核对与根因

两个入口共用 `GroupPathSequenceDeviceAddView` 及三种模式子视图。Site 通过 `GroupPathSequenceBrowseConfiguration` 注入候选浏览配置，差异来自这层配置，并不需要复制一个新弹窗。

| 项目 | Space → More → Trigger Zone | Site → Trigger Zone | 判断 |
| --- | --- | --- | --- |
| 问号入口 | `GroupPathSequenceAddDescriptionController.push`，传入当前模式和 Zone 语义 | 三种模式均调用 `GroupPathSequenceBrowseConfiguration.showHelp()`，展示一段 `SRAlertView` 提示 | 改为同一帮助控制器可实现一致导航 |
| 左侧菜单宽度 | 使用选择控件实时宽度 | `showSpaces` 使用控件宽度与 240pt 的较大值 | 240pt 下限导致窄屏菜单比选择器宽 |
| 左侧菜单方向 | 锚点设在控件下方 4pt | `showMenu` 比较上下可用高度，允许向上展开 | Site 当前策略直接违背固定下方的预期 |
| Quick 提示 | 设置 `space_trigger_zone_quick_add_hint`，位于选择器行下方 | 浏览配置显式隐藏提示；无可选 Space 时又借同一个 Label 展示状态 | 需恢复提示，并解除提示与状态文案混用 |
| Trigger 提示 | 设置同一提示 Key | 浏览配置将提示文字清空；状态 Label 展示未连接或不可用原因 | 需恢复提示，并调整状态 Label 的上边界 |
| Manual 提示 | 没有检测范围提示 Label | 没有该提示 | 保持一致即可，资格筛选仍适用 |

主要证据文件：

- [Site 控制器](../SunSmart/Main/Site/TriggerZone/SiteTriggerZoneViewController.swift)
- [Site 浏览配置与菜单](../SunSmart/Main/Group/Path/View/GroupPathSequenceBrowseConfiguration.swift)
- [Quick add 视图](../SunSmart/Main/Group/Path/View/GroupPathSequenceQuickAddView.swift)
- [Trigger add 视图](../SunSmart/Main/Group/Path/View/GroupPathSequenceTriggerAddView.swift)
- [Manually add 视图](../SunSmart/Main/Group/Path/View/GroupPathSequenceManuallyAddView.swift)
- [共用帮助页](../SunSmart/Main/Group/Path/Controller/GroupPathSequenceAddDescriptionController.swift)
- [通用菜单](../SunSmart/Common/View/TitleSelectView.swift)

## 建议交互规则

### 1. 问号进入同一帮助页

三种模式分别进入共用帮助页对应的 Quick、Trigger、Manual 内容，保持 `isSequence = false` 的 Zone 语义。关闭帮助页返回原 Site Trigger Zone 页面，保留选中 Zone、Space、分类及右侧筛选值。

当前帮助页存在两项内容差异：

1. Eligible Devices 文案写的是 current group，而 Site 的候选范围是所选 Space 内的合格 Group。
2. 帮助步骤描述真实自动添加、点击添加和拖拽；当前 Site 的 Quick Start 是空操作、Trigger 没有添加会话、Manual 仅浏览与筛选。

用户已知上述差异，并明确要求不增加 Site 上下文。因此三种模式直接使用原帮助控制器及原有内容、插图，不增加资格说明分支，不修改帮助页文案或本地化资源。Site 的实际浏览与筛选能力保持不变。

帮助页 push/pop 会触发 Site 现有页面生命周期，返回时重新读取候选数据。需要验证：已选择 Space 仍有效时保持选择；资格失效时按现有规则回退；帮助页打开前的异步结果不能覆盖返回后的新结果。无需预先重写加载机制。

### 2. Space 列表固定在选择器下方、等宽

- 使用实际点击的 Space 控件所属窗口和实时坐标，先完成布局再计算锚点。
- 菜单左边等于选择器左边；菜单宽度等于选择器实际宽度；顶部距选择器底部 4pt。
- 取消 Site Space 菜单的 240pt 最小宽度和向上展开策略。
- 保持现有选中高亮、不可选项置灰、点击外部关闭、有效 Space 回调及完整无障碍名称。
- 保持 Site 当前的 44pt 行高；列表高度不超过下方安全区可用空间，超过时滚动。可复用 `TitleSelectView.maximumHeight`，无需为了这项需求整体重写公共菜单。
- 长 Space 名称继续尾部截断，菜单不因名称变长而扩宽。窄宽度下权限原因可能被截断，需检查可读性及无障碍完整名称。
- 在支持的布局范围内保证下方至少一行可用空间。极端高度下优先局部调整面板布局以满足这一条件，不静默改回向上弹出，也不能点击后无响应。
- 旋转、窗口尺寸变化和页面离开时沿用现有关闭菜单行为，再次展开按新位置计算。

实现时为 Space 菜单单独指定“下方等宽”策略，避免改变同一个 helper 中右侧已添加设备筛选菜单的宽度和放置规则。

注意 `TitleSelectView` 当前把内容加到全局 keyWindow，而 Site helper 使用 `source.window` 计算坐标。实施时核对实际宿主窗口是否一致；若实际窗口测试发现差异，仅增加可选宿主窗口参数，默认行为保持兼容，不扩展为全局弹层重构。

### 3. Quick / Trigger 的检测范围提示

复用现有 Key `space_trigger_zone_quick_add_hint`：

| 语言 | 文案 |
| --- | --- |
| English | Only devices from proximity lighting groups will be detected |
| 简体中文 | 仅会检测邻近照明分组中的设备 |

现有英文已正确使用 `detected`，无需采用需求示例中的 `deteced`。分类名称已有正确的 `Manually add`，不新增拼写变体。

| 面板状态 | Quick add | Trigger add | Manually add |
| --- | --- | --- | --- |
| 已选 Zone，存在有效选中 Space | 选择器行下显示范围提示，下面保留 Start 区 | 选择器行下显示范围提示，下面继续显示 Not connected to a space | 不显示检测范围提示 |
| 所选 Space 有合格 Group，但设备为空或被过滤 | 仍显示范围提示，当前 Quick 行为保持 | 仍显示范围提示与现有未连接状态 | 按现有规则展示设备空态 |
| 无 Space、无合格 Space、无编辑权限、加载中或失败，当前没有有效 Space | 优先现有状态说明，隐藏检测范围提示 | 同 Quick | 保留现有状态说明 |
| 未选 Zone或当前处于步骤引导态 | 不展示范围提示 | 不展示范围提示 | 保持原引导 |

范围提示说明可检测设备的资格，不代表本轮接入真实检测或添加。

布局沿用 Space 风格：提示位于选择器行下方约 8pt，使用现有 12pt 辅助色字体、居中，并允许随可用宽度换行。提示宽度沿用内容区边距，不强行压缩到单个 Space 选择器宽度。

Quick 的范围提示与无可用 Space 状态使用独立 Label 或明确互斥的布局分支，避免把居中状态约束带回顶部提示。Trigger 的未连接/不可用状态上边界位于提示下方；隐藏提示时收回额外间距。

根据真实文字高度计算所需内容高度，继续使用当前三模式最大首选高度策略，避免普通切换分类时弹窗抖动。Manual 主动展开设备行仍使用原有高度逻辑。不能只删除隐藏语句而保留旧居中约束。

## 开发范围与顺序

| 步骤 | 涉及模块 | 工作内容 |
| --- | --- | --- |
| 1 | `GroupPathSequenceBrowseConfiguration`、三种模式问号回调 | 按模式进入共用帮助页，替换 Site 的单段提示弹窗 |
| 2 | `GroupPathSequenceAddDescriptionController` | 直接复用原控制器及现有文案，不增加 Site 上下文 |
| 3 | `GroupPathSequenceBrowseConfiguration.showSpaces/showMenu` | 独立 Space 菜单定位策略，等宽、下方、限高滚动；核对宿主窗口 |
| 4 | Quick、Trigger 子视图 | 恢复提示，分离状态文案，调整垂直约束和首选高度；Manual 仅沿用新的帮助与菜单 |
| 5 | 共用添加面板、Site 页面、现有 UI 探针 | 验证高度汇总、菜单回调、帮助往返状态和各种空态 |
| 6 | 共享品牌与资源 | generic iPhoneOS 构建，检查复用文案与帮助插图在各品牌的可用性 |

预计属于小到中等 UI 改动；主要工作量在状态切换与实际布局验证。无需修改 SDK、依赖或 Site 候选资格算法。本次仍保持 Site 已有浏览和筛选能力，不接入成员添加、保存、Mesh 连接或设备命令。

共享源码涉及 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux。文案与插图复用现有资源，不新增本地化 Key；不为了局部布局改动更改 target 配置。

## 验证方案与完成标准

沿用 `Tests/UI/SiteTriggerZoneCandidateLayoutProbe.swift` 的生产 UIKit 控件与控制器探针，只增加验证本次行为所需的检查。现有菜单探针只检查安全区、滚动和回调，没有检查“下方且等宽”，旧 PASS 不能证明本次目标成立。

需要覆盖：

1. 三种模式点击问号均进入正确模式的共用帮助页；关闭后 Zone、有效 Space、分类、筛选保持一致。Site 与 Space 复用同一帮助内容。
2. 菜单相对真实 Space 控件的左边、右边、底部锚点实际对齐；覆盖 1 项、8 项以上、长名称、选中项、禁用项与近底部位置；右侧筛选菜单回归。
3. Quick/Trigger 提示在正常态显示、Manual 隐藏；从异常态返回正常态后提示颜色、字号、点击属性和约束正确，不残留 Retry 行为。
4. 英文、简体中文，320/393/480/768pt 等容器宽度及重复宽度变化，检查提示换行、按钮/状态不重叠、菜单安全区、面板高度与 Manual 展开收起。容器宽度测试不等同于实际 iPad 或物理旋转验收。
5. 帮助页返回期间的加载与权限变化；未选 Zone、无 Space、无合格 Group、无权限、加载失败、未连接与设备为空等场景。
6. 当前 Quick Start 仍为空操作、Trigger 无检测设备、Manual 仍只浏览与筛选；Space/Group 原添加行为保持可用。
7. 运行现有 Site Trigger Zone 回归检查，并直接以 `xcodebuild` 对受影响品牌执行 Debug、iphoneos、generic/platform=iOS、关闭签名构建。检查英文和简体中文资源格式与 `git diff --check`。

方案阶段未运行真机、Simulator 或构建。实施阶段遵守项目规则：不使用 Simulator，未经本轮或后续明确要求不使用 Codex 做真机测试。实际 UIKit 布局应由用户按清单运行验收，或在用户后续明确要求真机自测时运行生产视图探针。静态检查和构建通过只能记为部分验证；实际布局未完成前，不将 UI 优化报告为全部验收通过。

## 用户确认记录

已确认：三种模式复用共用帮助页；Space 菜单固定下方等宽且限高滚动；有效 Space 状态下 Quick/Trigger 显示已有范围提示，Manual 不显示；无有效 Space 时优先原状态说明。

用户调整：“不需要补充 Site 上下文。其他确认”。按此范围实施，无需再次确认帮助内容。

后续代码改动与验证边界见[实施记录](260912_1409_site_trigger_zone_add_panel_ui_implementation.md)。
