# Site Trigger Zone 添加弹窗优化实施记录

日期：2026-09-12。工作树：`site-tz-plus`。基线：`4ec8c508`。

依据[已确认方案](260912_1351_site_trigger_zone_add_panel_ui_optimization_plan.md)，用户明确调整为“不需要补充 Site 上下文。其他确认”。本次直接复用原帮助页内容，没有新增 Site 帮助上下文。

## 已实现改动

| 项目 | 实现结果 |
| --- | --- |
| 问号帮助 | 移除三种模式中 Site 简单提示框的分支，按当前模式进入 `GroupPathSequenceAddDescriptionController`，保持 Zone 语义；原帮助页文案及插图不变 |
| Space 菜单 | 单独使用下方等宽策略，菜单左边与选择器左边一致，顶部距选择器底部 4pt；移除 240pt 最小宽度及向上展开逻辑 |
| 列表高度 | 保留 44pt 行高，按下方安全区限高，超过可见高度时滚动；保留禁用项、选中高亮和 Space ID 回调 |
| 弹层宿主 | `TitleSelectView` 增加可选 `hostWindow`，Site 在控件所属窗口计算位置并展示；旧调用不传参数时沿用原行为 |
| Quick add | 有有效 Space 时在选择器行下显示已有检测范围提示；异常状态使用独立 Label，避免与范围提示共用约束及重试行为 |
| Trigger add | 有有效 Space 时显示同一范围提示，未连接说明位于提示下方；没有有效 Space 时隐藏范围提示，保留原状态说明 |
| Manually add | 不增加检测范围提示；复用新的帮助跳转及 Space 菜单 |
| 高度和引导态 | 按提示实际文字高度计算 Quick/Trigger 所需高度；沿用三模式最大高度策略。进入引导态时解除隐藏浏览控件对提示间距的约束 |

提示继续使用 `space_trigger_zone_quick_add_hint`：英文为 `Only devices from proximity lighting groups will be detected`，简体中文为“仅会检测邻近照明分组中的设备”。没有新增本地化 Key、资源、依赖或 target 配置。

没有修改 Site 候选资格、成员数据、筛选业务、SDK、Mesh 连接或设备命令。Quick Start 仍为空操作，Trigger 仍没有实际检测会话，Manual 仍只浏览与筛选。

## 验证记录

| 检查 | 结果 |
| --- | --- |
| `scripts/check_site_trigger_zones.sh` | 通过：Zone 数据、29 个 Item 样例、候选读取/权限/Profile/身份/选择/筛选/失败状态 |
| `GroupPathSequenceDeviceAddViewContractTests` | 通过 |
| `SpaceTriggerZoneFollowupContractTests` | 通过 |
| 英文、简体中文资源及工程文件 `plutil -lint` | 通过 |
| `git diff --check` | 通过 |
| 最终品牌构建 | SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 全部通过 |
| UI 独立宿主 generic iPhoneOS 构建 | 通过，包含本轮修改的生产视图和布局探针；没有运行探针 |

构建直接使用 `xcodebuild -workspace SunSmart.xcworkspace`，选择对应品牌 scheme、Debug、iphoneos、generic/platform=iOS，并关闭代码签名。独立 UI 宿主位于 `/tmp/SiteZoneCandidateValidation`。本轮没有安装、启动真机 App，也没有使用 Simulator。

现有构建警告包括品牌资源中 `initiator` 名称冲突、部分品牌重复编译项及 Info.plist 资源项；未扩大范围修改这些既有配置。

## 已补充、尚未运行的实际布局检查

扩展 `Tests/UI/SiteTriggerZoneCandidateLayoutProbe.swift`，使用生产控件与生产页面，增加：

- 真实 Space 选择器与菜单的左右边缘、下方 4pt 锚点检查；100/186/260pt 控件宽度与 1/2/8/14 项菜单检查。
- Quick/Trigger 提示的显隐、原有本地化文案、字号、颜色和不可点击属性；与选择器、Start、未连接说明的间距检查。
- 三模式基础面板高度一致、异常态恢复正常态、退出选择后引导态不残留范围提示。
- 320×568、393×800、480×480、768×800 等容器尺寸及再次回到常规宽度的检查。
- 三种模式进入共用帮助页、复用原 Zone 资格说明、关闭后保留 Zone/Space/分类/右侧筛选的检查。

顺便修正原探针中已过时的筛选短标题预期，按当前基线的 `used` 文案检查；产品筛选文案没有变更。

以上探针已随独立宿主编译通过，但没有执行，因此不能报告实际布局或导航交互 PASS。已确认方案遵循默认不使用 Codex 真机测试、且不使用 Simulator 的规则；实际界面需后续由用户运行验收，或在用户明确要求真机自测后运行探针。

**当前完成口径：代码调整与构建检查已完成；实际 UI 布局和帮助页往返验收仍待执行，不能作为全部 UI 验收完成。**

## 最终构建记录

最终代码的以下 Debug generic iPhoneOS 无签名构建均返回 exit code 0：

| Scheme / 宿主 | 结果 |
| --- | --- |
| SunSmart | 通过 |
| Archipelago | 通过 |
| SLG Sync Plus | 通过 |
| SylSmart | 通过 |
| Lumineux | 通过 |
| `/tmp/SiteZoneCandidateValidation` 独立宿主 SunSmart | 通过，仅编译，不代表实际布局探针已执行 |

未创建 Git commit，未推送。
