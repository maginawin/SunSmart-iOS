# Group Profile 灵敏度提示重叠：原因与修复方案

日期：2026-10-27。分析基线：`fix/SR-BL2421-MINI-261027`，HEAD `54ccf2d6`；开始分析时工作树干净。用户随后确认实施，代码已修改，编译结果与运行验收边界见末节。

## 结论与证据边界

已确认两处布局缺陷：隐藏的调光速率卡片保留外部约束，导致特定 Profile 切换序列中底部约束冲突；灵敏度卡片的标题提示与百分比之间没有纵向避让约束。建议同时修复这两处，避免仅增加卡片高度掩盖状态切换问题。

用户截图证明重叠实际发生，但没有完整切换历史或 Auto Layout 日志。以下约束冲突可由当前源码确定；截图是否正好由该冲突打破了灵敏度高度约束，尚需运行时核对。不能据此声称“首次进入 Manual Control 后直接切到 Occupancy 必然出现 104 高度”。

## 行为链与原因

### 1. 隐藏的调光速率卡片仍约束内容高度

`ProfileSettingsViewController.headerViewDidSelectProfile` 切换草稿后调用 `updateUI()`；首次进入也调用同一方法。

- Manual Control、Daylight 不显示灵敏度。
- Occupancy with Daylight、Vacancy with Daylight、Daylight 显示调光速率。
- `updateUI()` 隐藏灵敏度时移除其 SnapKit 外部约束，但隐藏 `adjustSpeedView` 时只设置 `isHidden`，没有移除旧约束。
- 调光速率一旦显示过，便具有 top、固定高度 104 和到 contentView 底部的约束；之后隐藏仍参与布局。

最清晰的冲突序列：Daylight → Manual Control → Occupancy（也可 Daylight → Occupancy）。

1. Daylight 下调光速率位于 Power up behavior 下方，固定高度 `SCRYFrom(104)`，底边距离内容底部 `contentMargin`。
2. Occupancy 下灵敏度也放到 Power up behavior 下方，具有相同的顶部间距、底部间距，但要求高度 `SCRYFrom(130)`。
3. 隐藏的调光速率约束没有退出，两组约束同时要求这段空间分别为 104 和 130，无法全部满足。系统必须打破某条约束；不能保证具体选择哪一条。

另一条关联路径：Occupancy with Daylight → Occupancy。旧速率卡片仍要求位于灵敏度下方并连接内容底部，而新的灵敏度底边也直接连接内容底部，同样矛盾。修复须覆盖这两种旧 top 来源。

代码证据：`ProfileSettingsViewController.swift` 的 `updateUI()`（约 648–727 行）。本地 SnapKit `ConstraintMaker.remakeConstraints/removeConstraints` 仅处理对应 item 登记的约束；重建灵敏度的约束不会替调光速率移除其约束。

### 2. 灵敏度内部没有避让关系

`ProfileSensitivityView` 中：

- 标题顶部固定为 `SCRYFrom(16)`。
- 提示与标题中心线对齐、右边距 16，允许多行；只与 help 按钮建立横向避让。
- `showLackSensitivityNotice` 只更新提示显隐。
- 滑条容器固定高度 `SCRYFrom(76)`，底边距 `SCRYFrom(16)`，没有与标题或提示底边相连的 top 约束。
- 百分比由 `PowerUpLightSliderView` 显示，位于滑条容器顶部下方 `SCRYFrom(4)`。

因此卡片实际高度为 H 时，百分比顶部为 `H - SCRYFrom(88)`。H 为 130 时约为 `SCRYFrom(42)`；若卡片被压到 104，则变为 `SCRYFrom(16)`，恰与标题区重合。截图中百分比与标题同高，与这一推导吻合。

即使消除外部冲突，固定高度加独立定位也不能保证多行提示始终避开百分比。因此需要同时补上内部布局保障。

## 修复范围与方案

预计修改两个文件：

1. `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift`
   - 在统一刷新入口中，让隐藏的调光速率卡片退出外部布局约束；重新显示时沿现有分支完整重建。
   - 保留灵敏度现有隐藏清理机制，确保每次刷新只有当前最后一个可见卡片连接内容底部。
   - 初始化和刷新两处灵敏度高度约束保持一致，允许内容撑高，130 作为最小高度而非强制高度。
   - 不顺带清理 Timeout 的全部约束：Power up behavior 当前横向仍引用 Timeout，直接删除可能引入宽度未定问题。本次冲突应定向处理调光速率卡片。
2. `SunSmart/Main/Profile/View/ProfileSensitivityView.swift`
   - 保留标题、help、右侧橙色提示的现有排列。
   - 在本视图内建立可随内容增高的标题区域，由标题、help 和可见提示的最大高度决定；隐藏提示不占额外高度。
   - 滑条容器放在完整标题区域下方，保留明确最小间距（建议 `SCRYFrom(8)`），并保留现有底部间距及滑条高度。由完整纵向约束链确定卡片所需高度。
   - 提示出现、消失和反复切换均更新相关约束，不依赖延时刷新或手动 frame 修正。

继续复用 `PowerUpLightSliderView`，不修改其全局布局。该组件还用于 Power up behavior 的亮度/色温和 Proximity Lighting 的数量配置，直接修改共享组件会扩大影响面。无需新通用组件或新依赖。

保持现有提示判定：当前 Profile 显示灵敏度，且 Group 中存在 `isExternalLightSensorCapableLuminaire` 节点。Group 为 nil、空 Group 或不匹配该能力时不显示提示。此处只修布局，不重新定义设备能力。

## 关联影响

- 已有 Group 的 Profile 编辑和只读展示使用同一控制器；新增 Group 也复用该控制器，但传入 group=nil，不显示提示。
- SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 以及工程中的 HSmart target 共享该页面代码（已核对 Sources build phase），布局修复同步生效；本次不调整资源归属、国际化 Key 或品牌配置。
- 滑条与加减按钮仍通过原 delegate 更新草稿 `selectProfile.sensitivity`，保存仍走原回调。无需改持久化、导入导出、同步任务、SDK、固件或服务端，也无需历史数据迁移。
- 放宽卡片高度后，下方调光速率卡片和滚动内容高度应跟随更新；需检查滑到底部时无裁切或多余空白。

## 验证与验收

实施后先核对约束完整性，再运行一次 SunSmart Debug generic iOS 编译；构建前按项目规则核对本地 workspace/SDK 映射。本次纯共享布局修改无品牌分支差异时，不机械重复五品牌构建。

现有 `ProfileManualOverrideTimeoutTests.py` 替换了 UIKit 布局，不能证明本问题修复；不新增只匹配源码文本的“布局通过”测试，也不新建临时 Xcode 工程。

人工运行重点：

| 条件或操作 | 预期 |
| --- | --- |
| 含提示设备：首次打开 Manual Control → Occupancy / Vacancy | 提示、百分比、滑条分离 |
| Daylight → Manual Control → Occupancy，多次往返 | 无旧速率卡片约束残留，无高度冲突 |
| Occupancy with Daylight / Vacancy with Daylight → Occupancy，再切回 | 隐藏速率卡片退出布局；显示时位于灵敏度下方 |
| 两类 Proximity Lighting 与 Manual Control 往返 | 灵敏度正常恢复，下方内容与底部连接正确 |
| 无匹配设备、空 Group、新增 Group | 不显示提示，无额外提示空位 |
| 英文两行/更多行、简体中文、较窄 iPhone 和 iPad 页面 | 文案完整，提示与百分比不相交，卡片可撑高 |
| 0%、95%、100%，滑动及加减后 SAVE，再次进入 | 数值更新和保存结果保持原有行为 |
| 只读进入 Profile | 正常展示，保持原编辑限制 |

最终需要真实 UIKit 运行确认重叠消失，并检查调试控制台无相关 unsatisfiable constraints。截图对应的完整切换历史与具体断开的约束尚未取得；本轮未自动操作真机。

## 已实施与验证结果

- 用户确认后完成上述两个 Swift 文件的修改，未提交。调光速率隐藏时移除其外部 SnapKit 约束；重新显示仍由现有分支重建。
- 灵敏度标题行采用 UIKit `UIStackView`，包含标题、help、弹性空位和右侧提示，垂直居中。提示隐藏时自动退出 arranged subviews 的布局占位；可见文案保持纵向抗压缩，换行撑高标题行。滑条位于标题行下方 8 个适配单位，底边距 16、高度 76；外部两处高度约束改为至少 130。
- `git diff --check` 通过；复查变更只涉及上述布局代码，没有更改提示能力判定、数值回调或保存链路。没有运行或新增以源码匹配代替布局效果的测试。
- `SunSmartLocal.xcworkspace` 成功解析 SunSmart scheme。SDK realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，revision `9998967`，核对时无未提交差异；本次未改 SDK 或依赖。
- SunSmart / Debug / iphoneos / generic iOS / `CODE_SIGNING_ALLOWED=NO` 编译完成，xcodebuild 退出码 0。使用独立稳定目录 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-fix-SR-BL2421-MINI-261027-profile-layout`，没有 clean 或删除共享缓存。
- 编译输出包含依赖/既有代码警告，以及 CryptoSwift、DeviceLightViewController 的 `command failed with exit code 0 but produced no further output` 工具诊断；整体构建退出码为 0，不将其表述为无警告构建。最初沙箱内 workspace 查询受 Xcode 服务访问限制，沙箱外同入口解析成功后完成编译，未切换正式 workspace。
- 未运行 Simulator、未安装或运行真机；上述人工验收矩阵仍待验证。最短验收：在含提示设备的 Group 中执行 Manual Control → Occupancy，以及 Daylight → Manual Control → Occupancy，再来回切换，检查提示/百分比不重叠、下方卡片位置正确，并修改灵敏度保存后重进。
