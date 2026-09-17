# Export Json 入口配置方案

日期：2026-09-17。状态：用户确认的最小方案已实施，自动化与 Debug 构建通过，待人工体验验收。

## 结论与范围

三个 `Export Json` 菜单定义均接入 `sites.site.exportJson`，使用现有 `FeatureVisibility` 判断构建模式与当前资源角色。当前配置为仅 Debug 的 Owner、Editor 展示。

本次建议保留导出实现现有的 Debug 编译边界，在其内部接入配置。这满足本次给定规则，并支持通过配置收窄角色或关闭入口；不承诺以后只修改 `builds` 就能开放 Release 导出。若目标是让 Release 也完全由 JSON 决定，需要采用下文的完整迁移范围。

方案确认后已修改生产代码和实际 JSON，按下文最小范围实施；未执行真机安装或运行。

## 入口清单与角色来源

| 用户路径 | 实际入口 | 判断角色 | 导出范围 |
| --- | --- | --- | --- |
| Site → 右上角菜单 → Export Json | `SiteViewController.moreClick()` | `site.permission` | 当前 Site；沿用现有有权导出的 Space 筛选 |
| Site → Space 卡片 → 右上角菜单 → Export Json | `SiteViewController.spaceMenu(space:point:)` | 该卡片的 `space.permission` | 该 Space |
| Site → Space → 右上角菜单 → Export Json | `SpaceViewController.moreClick()` | 当前 `space.permission` | 当前 Space |

代码依据：[SiteViewController.swift](../SunSmart/Main/Site/Controller/SiteViewController.swift)、[SpaceViewController.swift](../SunSmart/Main/Space/Controller/SpaceViewController.swift)。

Site 的 All Spaces 和 Favourite Spaces 两组卡片，通过 `SpacesViewCellDelegate.cell(_:moreAction:)` 调用同一个 `spaceMenu`。Favourite Spaces 是同一入口的另一展示位置，不需要新增配置项。

配置路径是功能标识，不规定角色一定取 Site。尤其在 Site 为 Editor、某个 Space 为 Visitor 时，Site 入口可以展示，该 Space 的两个入口应隐藏。

检索 `debug_export_json` 文案引用、`DebugCloudJSONExporter` 使用点及 JSON 分享代码后，当前 App 源码未发现第四处同功能菜单定义，也未发现其他调用该 exporter 的业务入口。

### 其他相关导出代码

| 位置 | 现状 | 本次处理 |
| --- | --- | --- |
| `SpaceRecoveryViewController` → Saved Copies → 选择文件 | `SpaceSavedCopiesViewController` 分享已有 JSON 副本 | 属于恢复资料分享，不纳入此开关 |
| `SiteViewController.exportSpace(_:)` | 旧 Space JSON 导出方法；当前检索仅有定义，没有调用 | 不启用、不改动 |
| `SitesViewController` 分享方法中的 JSON 导出片段 | 已注释 | 不计为有效入口 |
| `GroupViewController.exportPhaseLuxFile()` | 光感采集 JSON 导出代码，采集结束路径有调用 | 属于光感数据，不纳入此开关 |
| `DeviceLightViewController.exportRouteTableFile(nodes:)` | 路由 JSON 导出代码；菜单中的 `readRoute()` 调用已注释 | 不计为同功能入口 |
| Space Debug 的 UART 分享 | 独立日志分享流程 | 不纳入此开关 |

上述区分针对同一个 Site/Space 配置导出功能，不把所有文件分享或所有 JSON 文件统一隐藏。

## 配置与行为

在 [debug_features.json](../SunSmart/debug_features.json) 的 `sites.site` 下增加 `exportJson`，与现有 `triggerZone` 并列，保留现有规则。新增项使用用户给定的 `builds: ["debug"]`、`roles: ["owner", "editor"]`。

在 [FeatureVisibility.swift](../SunSmart/Common/Config/FeatureVisibility.swift) 的 `Feature` 中注册 `siteExportJson`，原始路径为 `sites.site.exportJson`。无需修改解析器或另建配置管理器。

| 构建 / 当前资源角色 | Owner | Editor | Visitor / 无角色 |
| --- | --- | --- | --- |
| Debug | 展示 | 展示 | 隐藏 |
| Release | 隐藏 | 隐藏 | 隐藏 |

- 延续缺失、无效规则和空列表默认隐藏的行为，不回退到旧的硬编码展示规则。
- 包内配置首次加载后缓存，修改配置需重新构建安装；不引入热更新。
- 每次打开菜单传入当前资源角色，不缓存上一次的可见性结果。
- 不额外叠加 `spaceOperates`、临时编辑禁用或 OTA 编辑锁作为展示条件；本次保持按角色判断的原有语义。
- 可见性不授予导出权限；对象状态、账号、区域、归属和异步期间变化的检查继续由现有 exporter 负责。

## 最小实施方案（已完成）

1. 增加配置项和 `siteExportJson` 枚举值。
2. 三处菜单生成逻辑以 `FeatureVisibility.shared.isVisible` 替代现有 `canExport` 展示判断，分别传入表格中的角色。保留菜单顺序、图标、国际化 key、`performsActionAfterDismiss` 和宽度计算。
3. 在共享 `DebugCloudJSONExporter.share(site:space:from:)` 的入口，使用当前 `space?.permission ?? site.permission` 再检查该配置规则。被规则拒绝时直接结束，不生成文件；保留已有业务权限检查和提示。这样覆盖菜单展示后角色变化及三个入口的统一执行检查，无需在三个闭包重复实现。
4. `canExport` 继续负责业务权限与 Site 导出时的 Space 筛选；不把它改成配置判断，避免修改展示规则意外改变导出数据范围。快照校验、只读导出及文件清理逻辑保持原状。
5. 同步更新相关行为测试及旧菜单提取脚本。

生产修改预计涉及现有五个文件：JSON、FeatureVisibility、两个页面控制器、DebugCloudJSONExporter。不新增资源或本地化 key，不修改 SDK，不调整 workspace 或正式依赖。

### Debug 编译边界

当前两个页面的 exporter 属性、三处菜单、菜单宽度，以及 `DebugCloudJSONExporter`、`DebugCloudJSONFile` / `DebugJSONExportDiagnostics` 都受 `#if DEBUG` 限制。`ExportData.swift` 的 `debugInspection` 分支和 `SpaceConfigurationSafety.swift` 的诊断快照方法也有同样限制。

因此，推荐的最小方案实际展示条件为“构建包含此功能，并且配置的 builds 与 roles 同时匹配”。对本次指定的 Debug 规则，结果与需求完全一致；与既有通用配置能力相比，Export Json 暂时保留了仅 Debug 可用的特例，必须在实施记录中明确。

若要求与 `FeatureVisibility` 的通用语义完全一致、未来改 JSON 即可开放 Release，则应选择完整迁移：统一移除上述导出功能链的编译限制，让 Release 也能编译 exporter、诊断类型、只读导出分支和快照方法，再由配置隐藏入口。日志本身仍保留 `#if DEBUG`。同时更新依赖旧 `#endif` 定位的测试提取脚本，增加 Release 导出链编译及隔离验证。不能只移除三个菜单处的条件编译，否则 Release 会引用不存在的类型/API。本轮不默认扩大到此范围。

## 验证计划

### 自动化

- 扩展 `Tests/Config/FeatureVisibilityTests.swift`：覆盖 exportJson 的 Debug/Release × Owner/Editor/Visitor、缺失规则、空列表和无效规则；验证与 triggerZone 相互独立及配置注册一致。
- 增加最小菜单行为覆盖，复用现有隔离 fixture：验证三个真实菜单片段的配置关闭、Owner/Editor 可见、Visitor 隐藏，以及 Site/Space 角色不同时正确取值。验证共享执行入口在角色从 Editor 变为 Visitor 后不再发起导出。测试应调用实际生产判断，不只匹配源码字符串。
- 调整 `scripts/prepare_debug_json_ui_tests.py`：它当前按 `if DebugCloudJSONExporter.canExport(` 提取菜单；改为新判断后必须更新定位，并为 fixture 加入 FeatureVisibility、所需角色定义及配置资源。该脚本当前只提取 Site 和 Space 页右上角两处菜单；卡片入口需由前述行为覆盖补齐。
- 执行 `scripts/check_feature_visibility.sh` 和 `scripts/check_debug_json_export.py`。后者现有快照 fixture 不覆盖 UIKit 的 `share` 入口，不能用其通过代替新增执行检查的测试。
- `check_feature_visibility.sh` 中“Space 不受 Site Trigger Zone 影响”的断言检查的是 `SpaceMoreViewController`，本次修改的是 `SpaceViewController`，应保留原断言。
- 检查五品牌的 FeatureVisibility 源码和 JSON 资源仍各自归属正确；本次不新增资源引用。

### 构建和人工验收

实施前核对 `SunSmartLocal.xcworkspace` 及 SDK realpath。最小方案完成后运行 SunSmart generic iOS Debug 构建；不使用 Simulator、不默认安装真机。此方案保留原有 Release 编译分支，可通过现有配置隔离测试验证 Release 隐藏，不机械增加五品牌双配置构建。

若选择完整迁移，新增 Release 编译链会影响共享模块，需补 SunSmart Release 构建，并在合入前核对及覆盖受影响品牌的编译风险。

人工验收只需：Debug Owner/Editor 分别打开 Site、All Spaces/Favourite Spaces 卡片、Space 页面菜单，确认展示且能分享；Visitor 对应入口隐藏；配置关闭后全部隐藏；英文和中文菜单无截断。编译和隔离测试不代替实际分享面板及菜单体验验收。

## 调查基线与交接

- 工作树：`/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/debug-features`。
- 分支：`debug-features`；HEAD：`594e0520f5ec384d04ebaac8de418411fc27f87f`。
- 开始调查时无未提交改动；当前未提交差异包括上述五个生产文件、配置/菜单行为测试、验证与 UI fixture 脚本及本文。未创建提交。
- SDK：`SunSmartLocal.xcworkspace` → `.local-sdk/nordic-sig-mesh-sdk` → `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`；revision 为 `a971027e08f9775d7a3f071a06f89be1c38ecc96`，核对时无未提交差异。本次未修改 SDK、未新增 SDK API 依赖。
- 已完成：入口及调用链核对、配置接入、共享导出入口重查、回归测试及代表 target 构建。
- 未完成：人工菜单/分享面板体验验收。下一步按上文最短人工步骤确认。

## 实施验证结果（2026-09-17）

- `scripts/check_feature_visibility.sh` 通过：Debug 和 Release 隔离编译分别覆盖 108 个配置组合、54 个当前构建组合、异常配置与规则独立性，以及 81 个真实菜单片段组合。Debug 验证了三个入口的过期角色拦截、配置关闭后直接调用拦截和业务权限保留。Release 菜单片段保持不编译；这不是 Release App 构建结果。
- 同一脚本确认五品牌各包含一份 FeatureVisibility 源码和一份 JSON 资源；原有 Site Trigger Zone 行为回归通过。
- `scripts/check_debug_json_export.py` 通过：快照角色/账号/区域与一致性、原始记录、文件语义、命名、失败及清理路径。
- `scripts/prepare_debug_json_ui_tests.py` 已更新菜单提取、真实 Permission 定义、FeatureVisibility 源码及 JSON 资源，Python 语法检查通过；没有生成或运行额外的 UI 测试工程。
- SunSmart Debug 构建通过：`SunSmartLocal.xcworkspace`，`iphoneos`，`generic/platform=iOS`，`CODE_SIGNING_ALLOWED=NO`；DerivedData 为 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-debug-features`。构建包含现有依赖及废弃 API 警告。初次沙盒执行无法访问 Xcode 服务，使用已授权的沙盒外同命令后成功。
- 未执行真机验收；没有将隔离菜单测试视为真实布局/分享面板验收。
