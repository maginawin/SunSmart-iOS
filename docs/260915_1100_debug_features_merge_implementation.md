# Site Trigger Zone 合并与可见性配置实现总结

## 1. 合并结果

- 将 `site-tz-plus` 的已提交内容合入当前 `debug-features` 分支，HEAD 从 `14e37433` 快进到 `2e875e1f`。
- 两条分支之间无需人工文本冲突处理。合并时使用 autostash 临时保存本轮工程配置改动，随后自动恢复；没有残留未解决冲突或 autostash。
- `site-tz-plus` 工作树中的未提交同步修复仍保留在原工作树，没有纳入本次合并。
- 合并前的本轮配置文件备份位于 `/tmp/debug-features-before-merge-260915_105650`。

## 2. 正确功能入口

**Sites → Site → 右上角菜单 → Trigger Zone**。

`SiteViewController.moreClick()` 通过 `makeSiteTriggerZoneMenuItem()` 创建菜单，点击进入 `SiteTriggerZoneViewController(site:)`。

本轮对 Space More 页的错误接入已经全部撤回；Space 和 Group 同名功能沿用原有行为。

## 3. 配置与行为

文件：`SunSmart/debug_features.json`，与 `devices_config.json` 同目录。

每个叶子规则为包含 `builds` 与 `roles` 数组的对象，使用嵌套层级。是否展示要求两个维度同时匹配。

| 字段 | 可用值 | 示例功能当前配置 |
| --- | --- | --- |
| `sites.site.triggerZone.builds` | `debug`、`release` | 仅 `debug` |
| `sites.site.triggerZone.roles` | `owner`、`editor`、`visitor` | `owner`、`editor` |

| 当前 Site 角色 | Debug | Release |
| --- | --- | --- |
| Owner | 展示 | 隐藏 |
| Editor | 展示 | 隐藏 |
| Visitor | 隐藏 | 隐藏 |

- 使用当前 `site.permission`，该值来自 Site 云数据的 `role` 字段；不使用单个 Space 的角色或其编辑能力替代 Site 角色。
- 每次打开菜单重新判断，点击已打开的菜单时再次判断，防止角色变化后通过旧入口进入。
- 操作校验保留 `site.canManageSiteTriggerZones`，要求 Site 正常且存在可编辑 Space；无操作权限时使用已有 `no_permission` 文案提示。
- 即使将 roles 配成所有角色，也只改变入口可见性，不授予页面编辑或设备操作权限。
- 要让功能在两种构建中展示，在 builds 中同时列出 `debug`、`release`；仅在 Release 展示则只列 `release`。
- 任一列表为空、规则缺失、已知值无效时隐藏；单条错误隔离到该功能，文件整体无法解析时全部关闭。
- Debug 与 Release 均读取包内 JSON，首次访问后缓存；配置更改需要重新构建安装。

## 4. 文件改动

| 文件 | 内容 |
| --- | --- |
| `SunSmart/Common/Config/FeatureVisibility.swift` | 构建模式、规则解析、缓存、角色组合判断 |
| `SunSmart/debug_features.json` | Site Trigger Zone 默认规则 |
| `SunSmart/Main/Site/Controller/SiteViewController.swift` | 正确菜单生成与点击校验 |
| `SunSmart.xcodeproj/project.pbxproj` | 五个品牌的共享 Swift 与 JSON 引用 |
| `Tests/Config/FeatureVisibilityTests.swift` | 规则矩阵及异常配置验证 |
| `Tests/Config/SiteTriggerZoneMenuTests.swift` | 实际菜单方法的角色刷新、导航及拒绝操作验证 |
| `scripts/check_feature_visibility.sh` | 提取原始 Permission 和菜单方法执行测试，并核对五个 target 引用 |

## 5. 验证结果

- 配置测试已通过：54 种基本组合、27 个当前编译模式判断、未知／缺失角色、异常配置、局部错误隔离、一次加载缓存。
- 分别以 Debug 和 Release 条件编译执行规则及菜单测试，均通过。
- 菜单测试直接执行从当前 Site 控制器提取的方法，验证旧入口拒绝、最新 Site 角色、无操作权限提示和正确目标页面；导航及 HUD 使用记录调用的测试替身，不替代 UIKit 实测。
- 合入功能的 `scripts/check_site_trigger_zones.sh` 已通过：数据与重启恢复、29 种条目场景、候选项、只读拓扑和同步计划。
- 五品牌资源引用检查与 `git diff --check` 已通过。
- 五品牌的十项 iPhoneOS 构建全部通过；均直接运行 `xcodebuild`，generic iOS destination，`CODE_SIGNING_ALLOWED=NO`，没有使用 Simulator。

| 品牌 | Debug | Release |
| --- | --- | --- |
| SunSmart | 通过 | 通过 |
| Archipelago | 通过 | 通过 |
| SLG Sync Plus | 通过 | 通过 |
| SylSmart | 通过 | 通过 |
| Lumineux | 通过 | 通过 |

十份 `.app` 中的 `debug_features.json` 均已核对，文件哈希与工作区配置一致。构建中存在工程已有的废弃 API、重复资源名称及第三方依赖警告，本轮没有为此改动无关模块。

上述构建用于编译校验，产物未签名，不能直接安装到真机。手动安装须按 [MiPAD 命令行安装说明](260915_1113_mipad_command_line_install.md) 重新构建已签名包。

### 布局检查边界

已检查现有 MenuPopView 的菜单宽度、固定行高、按条目数计算的 tableView 高度及上下边缘约束。隐藏功能时不添加菜单项，菜单高度随条目数量收拢；保留现有 Debug 文本测宽和 Release 菜单宽度行为。本轮没有修改菜单布局约束。

按用户要求停止自动真机测试，最终布局和交互由用户手测。不能将上述构建、规则测试或约束检查视为真机 UI 验收通过。

## 6. 用户手测清单

配置场景更改后需重新构建安装，完成后将配置恢复为 Debug + Owner／Editor。

1. 默认配置：Debug 下 Site Owner、Editor 可以在右上角菜单看到 Trigger Zone；Visitor 看不到；Release 下所有角色看不到。
2. builds 同时包含两种模式时，两种构建都按 roles 展示；仅包含 release 时，Debug 隐藏、Release 按角色展示。
3. roles 分别配置为仅 Owner、Owner／Editor、全部三个角色，核对 Site 角色与入口结果。
4. 可见但没有可编辑 Space 时，点击提示无权限；权限允许时进入 Site Trigger Zone 页面。
5. 打开菜单后角色改变，再点击旧入口应被拦截；重新打开菜单应按新角色展示。
6. 英文与简体中文、iPhone 与 iPad：菜单文字不截断，入口隐藏后无空白占位，剩余菜单项位置与点击正确。
7. Space More 和 Group Path Sequence 中的独立 Trigger Zone 功能保持原行为。

## 7. Git 状态

分支合并已完成。本轮功能可见性代码与文档保留为当前工作区修改，未额外创建功能提交，也未推送。
