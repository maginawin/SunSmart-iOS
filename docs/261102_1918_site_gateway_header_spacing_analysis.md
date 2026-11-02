# Site 网关入口隐藏后的空白占位：分析与修复方案

日期：2026-11-02。状态：用户已确认实施，代码修复及专项回归、代表性构建完成，真实页面待人工验收。

## 结论

修复前已从源码确认：网关列表/添加入口隐藏后，Header 内部已将该行高度收为 0，但 UICollectionView 的 Header 高度仍固定计入 `SCRYFrom(48)`。多余高度最终留在可见顶部控件与 Space Item 之间，也会影响空列表提示的位置。

该问题不限定只有 1 个 Space，也同时影响 All Spaces、Favourites。现已统一网关行显隐判断，并让 Header 高度只累加可见行；保留现有权限、状态统计及正常控件间距。

## 修复前触发条件

以下三个条件同时成立时，网关行被隐藏，但仍被计入高度：

1. 当前用户不是 **Site Owner**。
2. `showGatewayModels` 为空，即没有当前可展示、可配置的本地网关。
3. 没有同时满足“有效可编辑”和“未绑定网关”的 Space。有效可编辑对应 `canEditing && deviceOperates.contains(.edit)`，已有等价属性 `canEditGatewayAssociation`。

这里的 Site Owner 与 Space Editor/Visitor 是不同层级，不能只看 Space 角色。

| 场景 | 是否产生本次空白占位 |
| --- | --- |
| 非 Site Owner，仅 1 个 Space，角色为 Visitor | 会；没有有效编辑权限，网关列表和添加入口均隐藏 |
| 非 Site Owner，仅 1 个 Space，Editor 以 Visitor 访问后返回 | 临时禁用编辑标记仍生效时会 |
| 多个 Space，全是 Visitor，或所有编辑权限均暂不可用 | 会；条件与 Space 数量无关 |
| Editor 因密码待验证、权限失效、成员配置未就绪、配置恢复/清理保护、Mesh OTA 等原因不能编辑 | 若没有其他可用网关或可编辑且未绑定的 Space，会 |
| Editor 的可编辑 Space 均已绑定网关，但本地网关记录/Node/网络缺失，或网关均被权限过滤 | 会；“没有可展示网关”不等于“服务器没有网关” |
| Favourites 中有 Space 或没有收藏项 | 上述条件成立时同样会；没有收藏项时表现为空态向下偏移 |
| 非 Site Owner 的空 Site 页面仍然展示 | 网关行和统计行均可隐藏，仍剩一行高度；是否停留该页面取决于外层页面流程 |
| Site Owner，或存在可展示网关，或存在有效可编辑且未绑定的 Space | 不触发这一原因的占位；网关行有实际内容 |

## 修复前根因与生命周期证据

- [SiteViewController.swift](../SunSmart/Main/Site/Controller/SiteViewController.swift)：`viewForSupplementaryElementOfKind` 按上述条件设置 `showGatewayListView`；但 `siteGatewayHeaderHeight` 始终传入 `gatewayListHeight: SCRYFrom(48)`。
- [SiteGatewayHeaderLayoutPolicy.swift](../SunSmart/Main/Site/Model/SiteGatewayHeaderLayoutPolicy.swift)：`height` 无网关行显隐参数，无条件累加 `gatewayListHeight`。
- [SiteGatewayHeaderView.swift](../SunSmart/Main/Site/View/SiteGatewayHeaderView.swift)：隐藏网关行时，约束高度已经是 0，统计行会移到 Header 顶部。因此问题来自外层 Header 预留高度，而非按钮自身约束未收起。
- [SpaceViewController.swift](../SunSmart/Main/Space/Controller/SpaceViewController.swift)：选择以 Visitor 继续访问会设置 `disableEditorPermission = true`。新建 Space 页面时会重置为 false，但普通返回 Site 不会直接重置。
- [SiteData.swift](../SunSmart/Common/Data/SiteData.swift)：`reloadSpacesPreservingGatewayMetadata(changedSpaceIds:)` 在无归属变化时保留原 Space 实例。Site 的 `viewWillAppear` 随后执行 `setupData`，临时禁用编辑标记仍可参与权限过滤。
- [SpaceData.swift](../SunSmart/Common/Data/SpaceData.swift) 与 [GatewayModel.swift](../SunSmart/Main/Device/Gateway/Model/GatewayModel.swift)：Visitor、临时禁用编辑及其他配置保护会阻止有效编辑；`canConfigureGateway` 同样按有效编辑权限过滤非 Owner 的网关。

返回 Site 后的链路为：保留 Space 实例及其临时状态 → 重算可展示网关 → 隐藏网关行 → 外层 Header 仍计入该行高度。此方案不改变临时 Visitor 模式的生命周期。

非 Site Owner 且 Site 有 Space 时，现有策略仍显示网关状态统计行，包括 Internet Online、Internet Offline、No Gateway。这是可见内容，应保留。当前典型情况是 Header 按 96 个布局单位计算，但只有 48 个单位的统计行及间距，额外多出 48。实际屏幕尺寸经过 `SCRYFrom` 缩放。

## 已实施的修复

1. 在 Site 页面增加 `shouldShowGatewayList()` 作为唯一显隐判断：有可展示网关，或是 Site Owner，或存在有效可编辑且未绑定网关的 Space 时显示。复用 `canEditGatewayAssociation`，不增加新的权限规则。
2. 为现有 `SiteGatewayHeaderLayoutPolicy.height` 增加 `showsGatewayList` 输入，仅在可见时累加该行高度。Header 配置和高度计算调用同一个判断入口。
3. All Spaces、Favourites、三个空态位置继续复用统一高度函数；返回页面、刷新、权限/网关数据变化时沿现有 `setupData → reloadData/updateEmptyView` 入口重新计算。没有引入缓存或额外状态。
4. 保留 Header 内部已有的零高度约束、状态统计行、时区 Review & Sync 行、离线提示，以及正常的 8 个布局单位间距。移除的是隐藏行的额外占位，不把可见控件紧贴在一起。

生产改动仅涉及 `SiteViewController.swift` 和 `SiteGatewayHeaderLayoutPolicy.swift`，测试扩展在原有 `SiteGatewayHeaderLayoutPolicyTests.swift`。未新增组件、持久化格式/历史数据迁移、文案或资源；无 SDK、固件或后端配套。

共享实现覆盖当前工程的 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux、HSmart。没有与本修复相关的品牌差异编译路径，以 SunSmart 完成代表性 Debug generic iOS 构建。

## 已验证与限制

分析阶段的临时 Swift 探针确认旧策略多计 48 个布局单位。实施后的验证结果如下：

- 通过：`SiteGatewayHeaderLayoutPolicyTests --header-only`，覆盖三行的 8 种显隐组合、显隐反复切换、状态统计保留、两个列表的独立网关选择及空态位置。该选项只选择 Header 相关检查，默认完整运行仍保留全部原有检查。
- 通过：临时恢复旧的无条件累加高度后，新回归明确失败，确认测试能够捕获本次缺陷；没有改动工作树中的修复代码。
- 通过：`SiteGatewayOnlineStateContractTests`。这是已有源码契约检查，不代表真实网关运行验收。
- 通过：`SunSmartLocal.xcworkspace` / `SunSmart` / Debug / iphoneos / generic iOS / `CODE_SIGNING_ALLOWED=NO` 构建，退出码 0。仍有未改动区域的闭包捕获及不可达 default 警告。
- 构建使用 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-device-scene-261028-cli`；本地 SDK 实际解析到 `nordic-sig-mesh-sdk-worktrees/one-dev`，revision 为 `dbcf6f1`，检查时无未提交差异，本次未修改 SDK。
- 通过：差异空白检查。未修改工程文件、依赖配置、资源或其他任务代码；未提交 Git。

以下两项均已在修改前代码上复现，保留原状并单独记录，不能将完整套件标为通过：

1. 完整 `SiteGatewayHeaderLayoutPolicyTests` 在网关按钮宽度断言失败：测试期望 112，而现有实现下限为 100。本次未改动宽度、滚动代码及对应期望。
2. `SiteTimeZoneReviewSyncContractTests` 在资源归属计数断言失败：测试要求四个 App target，当前工程为六个。修改前后失败信息一致，前面的 Header/空态/Review 相关契约检查均已执行到该断言。未调整工程或放宽断言。

## 待人工验收

未自动安装或运行真机。隔离策略测试与编译不能证明 UIKit 真实布局、Header 复用和交互表现已经通过。

最短步骤：单 Space Visitor 进入 Site；Editor 以 Visitor 进入 Space 后返回；切换 All Spaces/Favourites。预期状态统计控件与 Space Item 之间只保留正常间距。再确认 Owner/正常 Editor 的添加入口、有网关的列表、恢复编辑后的入口均正常。

补充覆盖多 Space、无收藏、离线提示、Review & Sync 行及上下滚动后的 Header 复用。
