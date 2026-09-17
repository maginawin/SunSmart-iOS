# Site Trigger Zone 添加面板展开、收起动画分析与开发方案

日期：2026-09-12。工作树：`site-tz-plus`。源码基线：`4ed2f4f8`。

状态：用户已确认，已按本方案实施。分析阶段未修改产品代码、未运行构建或设备测试；实施与验证结果见[实施记录](260912_1600_site_trigger_zone_panel_animation_implementation.md)。

## 结论

优化合理可行，属于局部 UI 交互一致性修复，预计改动较小。

Site → Trigger Zone 与 Site → Space → More → Trigger Zone 共用 `GroupPathSequenceDeviceAddView`。Space 入口在面板首选高度变化时执行 0.25 秒 UIView 布局动画；Site 入口只修改高度约束，没有对应的外层布局动画。用户观察到的“Site 好像没有动画”有明确源码依据，但本轮没有实际运行界面对比。

建议在 Site 的高度承载层补齐与 Space 一致的动画，复用现有面板、折叠状态和内容高度计算，默认不修改共享面板与 Space 入口。

## 源码证据

| 位置 | 当前实现 | 含义 |
| --- | --- | --- |
| `SiteTriggerZoneViewController.loadView` | 选中可展示面板的 Item 后调用 `setCollapsed(false, animated: true)`；高度回调转给 `content.setPanelHeight` | 已表达自动展开意图，但没有执行父容器动画 |
| `SiteTriggerZoneContentView.setPanelHeight` | 保存首选高度、更新 `panelHeight.constant`、设置显隐 | 高度在后续普通布局中直接生效 |
| `GroupPathSequenceDeviceAddView.updateCollapseUI` | 更新箭头、正文显隐、附件按钮并刷新首选高度 | `animated` 参数本身没有启动 UIView/Core Animation 高度动画，不能仅凭传入 true 判断动画存在 |
| `SpacePathTriggerZoneController.updateDeviceAddViewHeight` | 修改高度约束，在允许动画时执行 0.25 秒 `UIView.animate`，闭包内调用页面的 `layoutIfNeeded` | Space 的平滑位移来自父页面布局动画 |
| `SpacePathTriggerZoneController.setupUI` | 高度回调在页面已允许动画且挂载到窗口时启动动画 | 初始化布局不会直接启动这层动画 |

相关文件：

- [Site 控制器](../SunSmart/Main/Site/TriggerZone/SiteTriggerZoneViewController.swift)
- [Site 页面布局](../SunSmart/Main/Site/TriggerZone/SiteTriggerZoneContentView.swift)
- [共用添加面板](../SunSmart/Main/Group/Path/View/GroupPathSequenceDeviceAddView.swift)
- [Space 参考控制器](../SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift)

## 预期行为

1. 选中允许展示添加面板的 Site Trigger Zone Item，折叠面板自动平滑展开。
2. 点击标题栏箭头，展开与收起均使用 0.25 秒、与 Space 相同的默认 UIView 缓入缓出曲线；不增加弹簧或回弹效果。
3. 面板底部继续固定在安全区上方 16pt；面板顶部和上方列表底部在同一动画中移动。
4. 收起保持现有 44pt 标题栏；展开高度继续由现有三模式最大首选高度策略决定。
5. 面板已展开时切换 Zone，如果目标高度相同，只更新对应内容，不先收起再展开。
6. Manual 设备行展开、收回等实际高度变化，沿用相同高度动画。普通分类切换在高度不变时不重复启动动画。
7. 首次布局、离开页面、旋转或窗口尺寸重排、Debug 预览状态恢复等程序性布局不额外启动面板动画。可见页面的正常高度变化按既有状态规则更新。

本轮所指“展开与收起”以添加面板标题栏箭头及选中 Item 自动展开为主；Manual 行数变化只作为同一高度通路的必要回归项。折叠时正文与箭头的显隐策略继续复用 Space 使用的共用实现。

## 开发方案

### 1. 给 Site 容器增加可选动画的高度更新入口

在 `SiteTriggerZoneContentView` 的高度更新方法中增加显式动画选项，默认关闭，保留现有调用兼容性。

- 先按现有权限和状态规则计算实际目标高度与显隐，再判断实际高度是否变化。
- 对已经显示的面板高度变化，在正确的旧布局基础上更新约束，并在 0.25 秒动画闭包内完成整个 ContentView 的布局。
- 动画覆盖面板与列表的共同父容器，避免只动画面板内部而导致列表边界跳变。
- 保留原有 750 优先级面板高度、列表最小 60pt、底部安全区及状态栏约束，检查短屏下实际可满足的高度。
- 普通 render、显隐切换及无需动画的布局继续使用默认入口，不将整个页面刷新包入动画。

### 2. 在 Site 控制器接入动画时机

- 将面板高度回调接入新的动画入口。
- 参照 Space：页面完成首次展示且属于当前可见页面时才允许用户交互动画；离开页面时关闭。
- 选中 Item 的自动展开及标题栏点击继续使用原有状态路径，不建立第二份折叠状态。
- 核对 `reload → configureBrowse → refreshPreferredHeight → setCollapsed` 的先后顺序，保证高度不会在动画启动前被普通布局消费。
- 动画期间新的高度目标应平滑衔接到最新状态。先验证当前默认 UIView 行为，必要时局部采用从当前显示状态继续的动画选项，保持 0.25 秒与同一曲线，不叠加多个互相竞争的动画。
- 高度回调也可能来自 `layoutSubviews`；落实去重和重入保护，避免“布局 → 回调 → 布局”重复触发。仅在测试发现需要时增加最小状态控制。

### 3. 控制改动边界

预计生产改动集中在 Site 控制器和 ContentView 两个文件。无需修改 SDK、候选资格、Zone 成员、保存、同步、Mesh 连接或命令行为；无需新增用户文案、国际化 Key、资源、依赖或 target 配置。

默认不调整共享面板接口、不重构多个入口的动画架构。如实现中证实共享代码存在阻碍，再记录具体原因并采用最小兼容修正。

## 验证与验收

### 静态检查与构建

- 检查面板、列表、状态栏、安全区的完整约束链；重点检查短屏约束优先级及布局回调重入。
- 执行现有 `scripts/check_site_trigger_zones.sh` 与相关面板回归检查，确认原有状态行为未受影响；这些检查不能证明动画流畅。
- 直接使用 `xcodebuild` 执行 Debug、iphoneos、generic/platform=iOS、关闭签名构建；先验证 SunSmart，并核对实际源码 target 归属，对引用改动的品牌执行构建检查。
- 执行 `git diff --check`。

### 实际 UI 验收

现有 `SiteTriggerZoneCandidateLayoutProbe.run` 显式关闭动画，现有交互测试也主要检查最终控件状态。因此既有探针通过不能证明本次动画生效。

需要独立保留动画开启的实际验证，优先复用生产 Site 控制器的预览数据，避免仅对一个孤立面板执行测试：

| 场景 | 验收要求 |
| --- | --- |
| 首次选中 Item 自动展开 | 从标题栏平滑移动到展开高度，标题、面板顶部与列表底部同步 |
| 箭头连续展开、收起 | 两个方向均存在中间帧，时长与 Space 接近，无高度瞬跳或停在中间状态 |
| 动画中快速反向点击 | 最终高度、正文显隐和箭头一致，无回弹到旧状态 |
| 已展开切换 Zone、候选异步刷新 | 同高度不抖动；新高度平滑更新；Zone、Space 和筛选状态正确 |
| Quick / Trigger / Manual | 原三模式高度策略正确，Manual 多行展开与回收流畅 |
| 无 Zone、只读、无候选、失败等状态 | 面板显隐及提示遵循既有规则，无误展开或残留不可点击区域 |
| 英文、简体中文；320/393/480/768pt 容器 | 不重叠、不越过安全区，短屏下列表最小高度和面板约束可满足 |
| 帮助页往返、旋转、预览切换 | 不在页面转场或尺寸重排时出现额外弹窗动画 |
| Space 参考入口 | 原展开、收起与 Manual 高度变化行为保持正常 |

动态验证应通过录屏或逐帧采样实际渲染位置（presentation layer）检查起点、中间帧、终点；只读最终 frame 或只等待按钮出现不足以证明动画存在。检查面板底部稳定、顶部与列表底部间距持续一致，并在实际 UI 中观察内容显隐是否与参考入口一致。

按项目规则，不使用 Simulator，默认不由 Codex 运行真机测试。开发后可先完成代码、构建与必要探针准备；实际布局和动画由用户运行验收，或在用户后续明确要求真机测试后由 Codex 执行。在实际验证前，只报告“代码与构建完成、动态 UI 验收待完成”。

## 待确认范围

建议确认：在 Site 添加面板外层补齐与 Space 相同的 0.25 秒高度动画，覆盖选中 Item 自动展开、标题栏展开收起和同一通路的 Manual 行高变化；沿用现有状态与布局规则，并按上述边界完成验证。
