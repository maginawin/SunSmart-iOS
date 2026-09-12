# Site Trigger Zone 选中 Item 后面板高度与底部间距优化方案

## 结论与范围

优化合理、可行。以 Site → Space → More → Trigger Zone 的 Add to Zone X 面板为基准，统一 Site → Trigger Zone 选中 Item 后的面板位置与常规展开高度。

本轮仅分析与规划，等待用户确认后开发。尚未修改生产代码或执行构建、实际 UI 测试。

## 代码核对结果

两个入口共用 `GroupPathSequenceDeviceAddView`，均使用 `.dynamicSelected`：取 Quick add、Trigger add、Manually add 三种模式首选内容高度的最大值，并设 160pt 下限，因此普通模式切换不应改变高度。

| 项目 | Site Trigger Zone | Space Trigger Zone |
| --- | --- | --- |
| 面板底部锚点 | 当前视图安全区底部再向上 16pt | 父视图底部向上 `max(kSafeAreaBottomHeight, SCRYFrom(16))` |
| 标题栏 / 模式栏 | 44pt / 44pt | 相同 |
| 内容卡片上 / 下间距 | 8pt / 8pt | 相同 |
| Quick add 底部提示距内容底部 | 6pt | 相同 |
| Quick add 首选内容高度 | 186pt 起，按提示和控件避让增高 | 双筛选布局为 186pt |
| Manual 多行展开 | 内容高度随行数增加 | 相同方向的既有行为 |

在父视图底部与屏幕底部重合、安全区高度同为 34pt 的常见全面屏场景下，Site 面板距底部 50pt，Space 为 34pt，Site 确实额外上移了 16pt。无底部安全区时，Site 固定 16pt，Space 使用按屏幕缩放的 `SCRYFrom(16)`，仍可能存在小幅差异。

Space 常规选中、Manual 单行时：Quick 内容 186pt，Trigger 内容 168pt，Manual 内容 136pt，因此首选展开总高度为 44 + 44 + 8 + 186 + 8 = **290pt**，不包含面板外部底部空白。Site 常规状态若三种内容均不超过 186pt，也应为 290pt；不能仅凭外观认定其面板自身一定更高。

Site Quick add 的多行页脚和提示测量可能在窄屏或较长文案下推高首选高度。该逻辑用于避免重叠，不应直接删除或将所有状态强制锁为 290pt。上述尺寸是源码推导，尚未通过运行中的 UIKit 布局实测。

主要参考文件：

- `SunSmart/Main/Site/TriggerZone/SiteTriggerZoneContentView.swift`
- `SunSmart/Main/Site/TriggerZone/SiteTriggerZoneViewController.swift`
- `SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift`
- `SunSmart/Main/Group/Path/View/GroupPathSequenceDeviceAddView.swift`
- `SunSmart/Main/Group/Path/View/GroupPathSequenceQuickAddView.swift`
- `SunSmart/Main/Group/Path/View/GroupPathSequenceBrowseConfiguration.swift`

## 建议开发方案

1. **统一面板外部底部间距。** 调整 Site ContentView 的底部约束，采用“安全区与最小设计间距取较大值”的 Space 规则，消除安全区之外重复叠加的 16pt。优先基于当前容器安全区实现等效规则，在安全区变化时更新；核对 iPad 容器与窗口安全区不同的情况，确保面板不侵入当前容器安全区。
2. **校准高度与内部留白。** 在相同容器尺寸、语言、选中状态和 Manual 行数下，对比两入口的实际 frame。常规状态以 Space 的 290pt 为基准；沿用共用的 8pt 卡片底部间距与 6pt Quick 页脚底部间距。若实测 Site 仍有非必要增高，仅修正 Site 浏览态的高度计算或约束，不整体缩小公共面板。
3. **保留内容容纳能力。** 窄屏、多行提示、无可用 Space / 读取失败消息及 Manual 多行展开允许必要增高；普通三模式切换继续采用统一高度。明确把“常规状态一致”与“长内容完整显示”共同作为目标。
4. **检查完整约束链与动画。** 核对状态栏 → 列表 → 面板 → 安全区，以及标题栏 → 模式栏 → 内容卡片 → 子控件的约束；保留列表与面板 8pt 间距和已有 0.25 秒动画。检查列表最小高度 60pt、面板高度优先级 750 在短屏下是否压缩面板并造成裁切，不扩大到无关列表样式调整。
5. **范围控制。** 优先仅修改 Site ContentView；仅在实测证明需要时修改公共组件中的 Site 浏览态分支。底部位置规则覆盖同一 Site 面板的展开与收起，避免收起时底边跳动；未选中时的引导内容和高度逻辑保持现状。保留候选筛选、权限、设备添加能力和数据行为；不新增文案、资源、依赖或 SDK 改动。

## 验证与验收

- 扩展已有 `Tests/UI/SiteTriggerZoneCandidateLayoutProbe.swift`，增加与 Space 面板在等价容器下的对照，测量面板总高度、面板距容器底部、内容卡片距面板底部、Quick 页脚距卡片底部。实际布局误差目标不超过 0.5pt。
- 覆盖英文、简体中文，320pt 窄屏、常规全面屏、无底部安全区、iPad / 较短容器；覆盖选中、切换三模式、收起展开、Manual 单行/多行、空候选、无可用 Space 和失败提示。
- 常规展开高度及外部底部间距与 Space 一致；长内容没有遮挡、文字裁切、约束冲突；安全区变化和动画期间底边稳定，列表底边同步移动。
- 按实际修改文件检查品牌引用。Site 文件现有记录涉及 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux；若修改共享组件，重新确认全部受影响 target，再直接运行对应 scheme 的 generic iPhoneOS 无签名 `xcodebuild`，不使用 shell 包装或日志重定向。
- 运行相关现有面板 / Space 回归检查以及 `git diff --check`；源码契约检查和编译通过不等同于实际布局验收。
- 遵循用户“不使用 Simulator 校验、默认不由 Codex 做真机测试”的要求，实际 UIKit 布局探针由用户在设备上运行并反馈；如果用户后续明确授权，再由 Codex 执行真机测试。未运行前应标记“实现与构建完成，实际 UI 验收待执行”，不得报告 UI 全部完成。

## 待用户确认

是否按“外部底部间距与 Space 一致、常规展开高度对齐 Space、长文案和多行设备仅按需增高”的方案实施？
