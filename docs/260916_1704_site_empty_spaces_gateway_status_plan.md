# Site 无 Spaces 时的网关状态入口优化方案

日期：2026-09-16。状态：用户已确认并完成实施；相关隔离测试及 SunSmart 编译通过，实际界面与点击跳转待人工验收。

## 结论与建议

选中一个有效且有配置权限的网关时，Internet status 组件应始终展示，与 Site 是否存在 Spaces、当前筛选结果是否为空无关。复用组件现有的设置按钮进入对应网关页面。

All Spaces 和 Favourites 使用同一规则，并保留各自独立的网关选择。Overview 沿用现有展示规则：空 Site 不展示 Spaces 统计栏；有 Spaces 时维持原行为。空列表提示排在状态组件下方。

## 已核实的原因与调用链

- 当前工作树为 `fix-gateway`，HEAD 为 `6430f8ec`；开始调查时无未提交改动。
- 实际入口为 `SunSmart/Main/Site/Controller/SiteViewController.swift`，不是 Space 页面。
- `setupData()` 正常加载网关、按 `site.canConfigureGateway` 过滤可见网关，并保存有效的选中项；无 Spaces 不会阻止 Owner 选择网关。
- `shouldShowGatewayStatus(for:)` 将 `!site.spaces.isEmpty` 作为必要条件，导致空 Site 的状态组件始终隐藏，即使已选中网关。
- 该判断同时影响头部渲染与 `siteGatewayHeaderHeight(for:)`；`emptyFrame(...)` 又依赖头部高度。因此组件可见性、头部高度、空状态位置必须一并使用新规则。
- `gatewayOperationClickAction` 已按 Wi-Fi/其他网关分发到 `WiFiGatewayViewController` / `GatewayViewController`。初始化和操作入口有权限校验，没有必须存在 Space 的门槛。

## 具体行为

| 场景 | 预期 |
| --- | --- |
| Site 无 Spaces，有可操作网关且选中该网关 | 展示单网关 Internet status 和现有设置入口；下方保留 No Spaces 提示 |
| Site 无 Spaces，选中 Overview | 保持隐藏统计栏，保留网关选择栏和 No Spaces 提示 |
| Site 无 Spaces，也无可操作网关 | 保持现有空状态与添加网关规则 |
| Site 有 Spaces，所选网关没有关联 Space | 状态组件与设置入口可用，下方显示筛选后的空状态 |
| Favourites 无条目，但选中了有效网关 | 同样展示所选网关状态；下方保留收藏为空提示 |
| 两个分页选中了不同网关，或一页选中 Overview | 各自显示对应状态，头部高度互不串用 |
| 网关删除、权限变化或刷新后选中项失效 | 复用 `setupData()` 的选择清理逻辑，退回 Overview，避免残留入口 |

“有效网关”指仍存在于 `showGatewayModels` 的网关，不只判断选中 ID 非空。Owner 在空 Site 可配置网关；其他角色继续遵循现有基于 Space 权限的规则。

## 实施结果

1. 扩展现有状态可见性判断，使有效的单网关选择优先显示；Overview 继续使用原条件。
2. 头部渲染、头部高度和空状态 frame 统一传入对应 collection view 的选择上下文，不能只读取当前 segmentedControl 索引，因为两个分页都会刷新和布局。
3. 复用 `SiteGatewayHeaderLayoutPolicy` 承载可独立验证的展示规则，并扩展现有测试覆盖空 Site、Overview、无效选择及高度变化。继续使用现有刷新与复用机制，核对选择变化后的布局更新。
4. 复用现有 `SiteGatewayStatusView`、状态填充和页面跳转。右侧设置按钮负责进入详情；状态文字区原有的同步失败重试交互保持原意。

实际修改：`SiteViewController.swift`、`SiteGatewayHeaderLayoutPolicy.swift`、`SiteGatewayHeaderLayoutPolicyTests.swift`、`SiteGatewayOnlineStateContractTests.swift`。按方法签名变化同步了现有接线契约检查；组件、文案、资源、网络请求和 SDK API 均复用现有实现。

## 状态值的现有限制

本方案修复组件可见性与入口。当前 `loadGatewaysData()` 在缺少关联 Space 的服务器状态时，将已激活网关显示为 Offline，未激活网关显示为未激活。因此空 Site 中已激活网关显示 Offline，不代表本轮已核实其真实 Internet 连通性。

本轮建议沿用该取值规则；如需空 Site 的独立实时在线状态，需要另查服务器网关状态来源，不能以 BLE 可连接或 Wi-Fi 信号代替 Internet 状态。

## 验证与交付

- `SiteGatewayHeaderLayoutPolicyTests`：通过。直接编译现有策略与测试文件，验证有效/失效选择、原有 Overview 规则、两页独立选择输入以及 review 卡片有无时的头部高度和空状态位置；包含网关删除后可见列表变化。此结果是隔离策略验证，不等同于真实 UIKit 页面验收。
- `SiteGatewayOnlineStateContractTests`：通过。直接编译并对 Site、Gateway 和 ImportData 执行现有契约检查，验证状态来源与新签名下的可见性共用关系；属于源码接线检查。
- 本次按风险直接运行上述相关测试，未运行整套网关/时区脚本。现有聚合检查中仍有“四个品牌”的固定计数，与当前五品牌工程不一致；本次未改动这些无关检查。
- SunSmart generic iOS Debug：构建通过，`xcodebuild` 返回 0。使用 `SunSmartLocal.xcworkspace`、`-sdk iphoneos`、`-destination 'generic/platform=iOS'`、`CODE_SIGNING_ALLOWED=NO`，DerivedData 固定为 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-fix-gateway`。输出包含未改动代码与依赖的弃用/Swift 6 兼容性警告。
- 共享代码覆盖五个品牌，本次无品牌条件、资源或依赖改动，仅执行 SunSmart 代表 scheme 构建。
- 本机 SDK 来源为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，revision `a6246b1`，实施前工作区干净；本次未修改 SDK，也未增加 SDK API 依赖。
- `git diff --check`：通过。

待人工验收：进入只有网关、没有 Spaces 的 Site → 选中网关 → 确认状态栏和空提示不重叠 → 点设置进入对应网关页面 → 返回并切换 Overview / Favourites。补查多个网关切换、删除后返回、离线或未激活显示，以及已有 Spaces 的正常页面。本次未安装或运行真机。
