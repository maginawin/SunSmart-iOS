# Site Trigger Zone 候选展示与筛选：开发和 MtestiPhone15 自测记录

日期：2026-09-12。工作树：`site-tz-plus`。基线：`86b97c5c`。未提交 Git、未推送。范围依据 [开发方案](260912_1119_site_trigger_zone_add_panel_plan.md) 及用户确认“本轮只展示与筛选设备”“使用 MtestiPhone15 自测”。

## 已实现行为

选中可编辑 Zone 或现有空 Zone 后，底部显示候选浏览面板，首次默认 Quick add。三种模式共享 Space 和已添加过滤状态。

| 功能 | 实际行为 |
| --- | --- |
| Space 选择器 | 展示当前 Site 已知的全部 Space；不提供 All；默认选中列表中首个有效 Owner/Editor 且有 Proximity Group 的 Space |
| 资格 | 支持 Proximity Lighting、Proximity Lighting with Photocell 两类 Profile；无合格 Group、权限受限、数据不可用项禁用置灰 |
| Manual | 当前 Space 的合格 Group 设备，统一离线样式；支持分页和展开行数；点击不选中、不 Identify、不添加、不拖拽 |
| Quick | 保留 Start 界面；点击不改变状态、不进入添加流程 |
| Trigger | 无检测设备；有合格 Space 时显示 `Not connected to a space` |
| 右侧过滤 | `Ignore added devices` / `Show the devices added in other Zones`；短标题为 `New only` / `Include added` |
| 过滤范围 | 只排除当前 Site 的 Site Zone 成员；当前 Zone 成员始终排除；Include added 同时保留新设备和其他 Site Zone 的成员 |
| Space 页面回归 | 三模式的展开菜单改用现有 Zones 文案；Space 的 All eligible groups 保留；Sequence 的 Paths 文案和原设备操作不变 |

空态区分：

- 无 Space：`No spaces`，无选中项，也不额外重复解释。
- 有 Space 但无合格 Group：`No eligible spaces`，下方 `Assign a Proximity Profile to a group in a space you can edit.`。
- 全部无有效编辑权限：`No editable spaces`，说明需要 Owner 或 Editor。
- 数据未知或损坏：显示加载/不可用状态，不当作无 Group；无可用 Space 时提供点按重试。
- 有合格 Group 但无设备：保留该 Space，不自动跳走，显示 `No devices`。
- 全被过滤：区分 `No new devices` 和 `No devices available to add`。

## 数据与副作用边界

新增 `SiteTriggerZoneCandidatePolicy`、`SiteTriggerZoneCandidateReader`、共享 `GroupPathSequenceBrowseConfiguration`，以及 Debug 专用候选样例。候选数据为独立值类型，身份包含 Site、Space、设备 UUID，不按不同 Space 的短地址合并。

Reader 使用系统 SQLite 的只读连接，显式限定 App/账号数据库、Mesh UUID、Space subnet、Group/Profile 作用域。先读取 Group 资格，再只读取选中 Space 的设备；再次检查数据库中的权限、Space 状态和密码待验证标记。排除 Provisioner、未完成配置节点、特殊/虚拟 Group，按现有 Node.group 的业务归属规则确定 Group。

读取不构造 Node、MeshNetwork 或 Key，不调用依赖当前全局 Mesh 上下文的 Group.nodes，也不调用会修复/保存数据的 MeshNetwork.load。数据库读取前后版本变化时丢弃混合结果；页面退出、切预览或账号/区域变化后的过期异步结果不回填。

设备解析失败的 Space 在一次刷新周期内保持不可用，避免多个坏 Space 在“资格正常、设备解析失败”之间被反复自动选中。显式刷新后可重新尝试。

真实 Site Zone 当前仍保留“只支持空 members”的原保护。因此真实模式两个已添加选项暂时显示相同结果；已有成员差异通过隔离 Debug 样例和策略测试验证。本期没有解禁非空持久化，也没有加入成员草稿或保存链路。

## 构建和自动检查

| 检查 | 结果 |
| --- | --- |
| `scripts/check_site_trigger_zones.sh` | 三组通过：既有空 Zone 数据、29 个 Item 样例、新增候选读取/策略测试 |
| `GroupPathSequenceDeviceAddViewContractTests` | 通过；更新浏览态与分页计数的契约断言 |
| `SpaceTriggerZoneFollowupContractTests` | 通过 |
| `plutil -lint` | 工程文件、英文和简体中文资源通过 |
| `git diff --check` | 通过 |
| SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux | 最终 Debug generic iPhoneOS 构建通过 |

新增候选测试包含：有效角色、密码待验证、两类 Proximity Profile、延迟设备读取、空 Group、重排后保持选择、无有效选择、不同 Space 相同地址、Provisioner 排除、配置状态排除、身份去重、当前/其他 Site Zone 排除语义、损坏 Profile/设备数据、缺失数据库不创建文件、读取前后数据库字节不变，以及多个坏 Space 不发生重复自动加载。

构建直接使用 `xcodebuild -workspace SunSmart.xcworkspace -scheme <品牌> -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`。没有使用 Simulator，没有修改 SDK 或依赖版本。新增 Swift 文件按既有共享文件 membership 加入相关品牌；新增文案同步提供英文、zh-Hans。

拓扑全量脚本 `scripts/check_path_topology_persistence.sh` 在原有断言 `Space import must preflight proximity data before destructive apply` 处失败。将其读取的源码从未修改的 HEAD 导出后重跑，同样失败。本期未改 ImportData 或该断言，不将这条基线问题计为通过，也未扩展修改导入模块。

## MtestiPhone15 实际验证

设备：MtestiPhone15，iPhone 15，iOS 26.6.1。使用独立测试包 `com.sunricher.site-zone-interaction-validation`，宿主位于 `/tmp/SiteZoneCandidateValidation`，编译当前工作树的生产视图和控制器。样例不写入用户真实 Site，测试不连接 Mesh。

XCTest runner 共尝试三次，包括沙盒外重试、真实 UDID 串行运行和关闭覆盖率；均在建立 IDE 连接前退出，错误为 `Connection peer refused channel request` / exit code 74。因此 `SiteTriggerZoneCandidateUITests` 没有执行成功，不能宣称 XCUITest 通过。

替代验证通过 devicectl 安装并启动独立 App，在 **MtestiPhone15 本机**执行 `Tests/UI/SiteTriggerZoneCandidateLayoutProbe.swift` 中的两组探针，中英文均返回 PASS：

1. 真实 UIKit 布局：320、393、480、768、回到 393pt 的重复容器宽度，三种模式，六类空态/设备场景，单行/三行、长名称、消息高度、控件边界与重叠、菜单安全区和滚动、离线静态设备、不可拖拽、Quick 无状态变化、Trigger 零设备。
2. 生产控制器交互：选 Zone 展开默认 Quick；通过实际 WMMenuView 切模式；通过生产菜单回调切 Space、切包含已添加；当前 Zone 排除、其他 Zone 包含、切 Zone 重算、展开行数、模式共享过滤、预览退出隔离。

这些交互探针调用生产控件 action/delegate，属于真机运行验证；没有通过系统级触摸注入执行 XCUITest。宽度变化测试运行在 iPhone 的容器中，不代表实际 iPad 或物理横屏验收。真实数据库投影由 SQLite 夹具测试验证，没有使用该手机账号下的真实业务数据做端到端联调。

首次运行时发现继承的 UICollectionViewFlowLayout 默认 itemSize 高度为 50pt，与候选单行容器的 44pt 不匹配。已仅在候选浏览布局中显式设置尺寸，复测不再输出该警告；同时补齐宽度变化时的列数、分页和展开状态刷新。

证据目录：`/tmp/SiteZoneCandidateEvidence/final-en`、`/tmp/SiteZoneCandidateEvidence/final-zh-Hans`，各自的 `result.txt` 和 `interactions.txt` 均为 PASS。渲染图由设备内真实 UIView/Window 的图层导出并人工检查；不是 Figma 截图，也不是 Simulator 截图。精选图保存在仓库：

| 场景 | English | 简体中文 |
| --- | --- | --- |
| Manual 生产页面 | [查看](assets/260912_site_trigger_zone_candidates/en-page-manual.png) | [查看](assets/260912_site_trigger_zone_candidates/zh-Hans-page-manual.png) |
| Trigger 未连接 | [查看](assets/260912_site_trigger_zone_candidates/en-page-trigger.png) | [查看](assets/260912_site_trigger_zone_candidates/zh-Hans-page-trigger.png) |
| Space 菜单 | [查看](assets/260912_site_trigger_zone_candidates/en-page-spaces.png) | [查看](assets/260912_site_trigger_zone_candidates/zh-Hans-page-spaces.png) |
| 已添加过滤菜单 | [查看](assets/260912_site_trigger_zone_candidates/en-page-added-filter.png) | [查看](assets/260912_site_trigger_zone_candidates/zh-Hans-page-added-filter.png) |
| 无合格 Space | [查看](assets/260912_site_trigger_zone_candidates/en-no-eligible-mode-2-rows-1.png) | [查看](assets/260912_site_trigger_zone_candidates/zh-Hans-no-eligible-mode-2-rows-1.png) |
| 无 Space | [查看](assets/260912_site_trigger_zone_candidates/en-no-spaces-mode-2-rows-1.png) | [查看](assets/260912_site_trigger_zone_candidates/zh-Hans-no-spaces-mode-2-rows-1.png) |

后续成员添加/保存、Quick 执行、Trigger 监听、跨 Space Key 和同步仍是独立阶段；本期交付候选展示与筛选。
