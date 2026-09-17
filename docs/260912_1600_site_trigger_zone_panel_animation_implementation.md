# Site Trigger Zone 添加面板动画实施记录

日期：2026-09-12。工作树：`site-tz-plus`。基线：`4ed2f4f8`。

依据[已确认方案](260912_1501_site_trigger_zone_panel_animation_plan.md)实施。

## 实现结果

- `SiteTriggerZoneContentView.setPanelHeight` 增加默认关闭的动画参数。实际高度变化时，使用 0.25 秒缓入缓出动画更新整个 ContentView 的布局，使面板顶部与列表底部同步移动。
- 增加从当前显示状态继续及允许动画期间交互的选项，用于连续点击和动画中反向操作。没有引入弹簧动画。
- 同高度更新直接返回；面板显隐变化、没有窗口及重入布局不启动新动画。刷新旧布局后使用最新首选高度，避免覆盖布局期间的新回调。
- Site 控制器把面板高度回调接入动画入口。完成首次展示后启用，进入/离开页面时关闭；尺寸转场期间暂停；Debug 预览切换期间临时关闭并恢复原设置。
- 标题栏按钮、选中 Item 自动展开、Manual 行数变化继续走同一面板状态与高度通路。

生产代码仅修改 Site 控制器与 ContentView。未修改 Space 入口、共用添加面板、SDK、候选资格、成员数据、Mesh 或同步行为。没有新增文案、本地化 Key、资源、依赖或 target 配置。

## 约束检查

保留原有约束：面板左右贴父容器，底部距安全区 16pt；列表底部距面板顶部 8pt；列表最小高度 60pt；面板首选高度优先级 750；收起标题栏 44pt。

动画在这些约束的共同父容器执行，不单独修改 frame。短屏仍按现有优先级处理，未调整内容高度策略。已检查静态约束链；实际短屏布局及动画期间内容显隐仍待运行验收。

## 已执行验证

| 检查 | 结果 |
| --- | --- |
| `scripts/check_site_trigger_zones.sh` | 通过：数据、29 个 Item 样例、权限与候选读取/筛选/失败状态 |
| `GroupPathSequenceDeviceAddViewContractTests` | 通过 |
| `SpaceTriggerZoneFollowupContractTests` | 通过 |
| SunSmart generic iPhoneOS 构建 | 通过 |
| Archipelago generic iPhoneOS 构建 | 通过 |
| SLG Sync Plus generic iPhoneOS 构建 | 通过 |
| SylSmart、Lumineux generic iPhoneOS 构建 | 全部通过 |
| 独立 UI 宿主 generic iPhoneOS 构建 | 通过，包含生产代码和新增动态探针；未运行 |
| `git diff --check` | 通过 |

已解析工程文件确认：两个生产文件同时被 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 引用。构建直接使用 `xcodebuild -workspace SunSmart.xcworkspace`，指定对应 scheme、Debug、iphoneos、generic/platform=iOS，关闭签名。没有通过 shell 包装或重定向构建日志。

构建中出现既有 `initiator` 资源名称冲突、部分品牌重复编译项和 Info.plist 资源项警告，未扩展范围修改。

## 动态探针与待验收项目

在 `Tests/UI/SiteTriggerZoneCandidateLayoutProbe.swift` 中新增独立的异步 `runPanelAnimations`。它要求生产页面已显示且动画开启，通过实际 presentation layer 采样检查：

- 选中 Item 自动展开、标题栏收起、再次展开存在中间位置。
- 面板底部保持不变；动画中列表底部与面板顶部保持 8pt 间距。
- 动画最终落到目标布局，收起后为 44pt。
- 收起进行中反向展开，以及 Manual 多行展开、收回。

探针独立于原先关闭动画的静态布局检查，避免将最终布局正常误判为动画生效。

本地独立宿主位于 `/tmp/SiteZoneCandidateValidation`，已接入启动参数 `candidate-animation-probe`。由用户在 Xcode 中选择真机运行该宿主、设置该参数，即可在页面查看 `candidate-animation-probe-result` 的 PASS 或失败说明。宿主与启动接线属于临时验证工具；可复用探针保存在仓库中。

**探针仅编译通过，未实际运行。** 英文/简体中文、不同容器尺寸、Space 参考入口对比、快速操作、候选异步更新及帮助页往返仍按方案执行实际 UI 验收。离散帧检查也不能代替对整体观感的观察。

遵循默认不由 Codex 做真机测试且不使用 Simulator 的约定，本轮没有安装或启动设备 App。当前完成口径为：代码与已列明检查完成，实际布局和动画验收待执行，不能报告 UI 全部验收通过。

未创建 Git commit，未推送。
