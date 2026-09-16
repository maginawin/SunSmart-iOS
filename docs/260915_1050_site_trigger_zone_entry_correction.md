# Site Trigger Zone 入口纠正

> 后续已按用户要求合入 `site-tz-plus` 并完成正确入口接入。最新状态见 [合并与可见性配置实现总结](260915_1100_debug_features_merge_implementation.md)。下文保留纠正时的核对记录。

## 用户明确的功能路径

`Sites → Site → 右上角菜单 → Trigger Zone`。

此前错误地将 `sites.site.triggerZone` 接入 `Site → Space → More → Trigger Zone`，两者是不同功能。

## 源码核对

- 当前工作树：`sun-smart-worktrees/debug-features`，分支 `debug-features`，HEAD 为 `14e37433`。
- 当前 `SiteViewController.moreClick()` 不含 Trigger Zone 菜单，源码中也没有 `SiteTriggerZoneViewController`。
- 正确功能位于 `sun-smart-worktrees/site-tz-plus` 的 `SiteViewController.moreClick()`，菜单使用 `menu_trigger_zone` 图标和 `trigger_zone` 本地化文本，进入 `SiteTriggerZoneViewController(site:)`。
- 该入口当前以 `site.canManageSiteTriggerZones` 控制生成和点击。该属性检查 Site 状态正常，且至少存在一个可编辑 Space。
- `site-tz-plus` 相对当前分支包含完整的 Site Trigger Zone 开发，分支差异为 123 个文件、约 1.3 万行新增；该工作树另有尚未提交的同步修复改动。

## 已纠正的工作

- 撤回本轮对 `SpaceMoreViewController.swift` 的全部修改，确认该文件与原始版本无差异。
- 移除本轮针对错误 Space 入口新增的 UI 测试和真机测试工程生成脚本。
- 保留 `FeatureVisibility` 通用规则管理器、`debug_features.json`、五品牌工程引用及配置行为测试。
- `sites.site.triggerZone` 配置仍为 Debug + Owner／Editor，但当前工作树尚无对应页面接入，不能宣称 Site 功能已受此配置控制。
- 真机布局与交互由用户自行测试；不再运行自动真机测试。此前自动测试运行器启动失败，没有获得布局验收通过结论。

## 正确接入方向

1. 在包含 Site Trigger Zone 功能的代码基线上开发。
2. Site 右上角菜单生成时根据当前构建模式与 Site 上下文角色判断可见性，不影响 Space 或 Group 的同名功能。
3. 点击时再次判断可见性，然后保留 `canManageSiteTriggerZones` 的业务操作校验；不满足操作权限时复用现有本地化提示。
4. 接入时核对 Site Owner、Space Editor 汇总到 Site 页面角色的实际模型语义，避免误用某个 Space 的角色。
5. 验证正确菜单、五品牌资源与构建，并提供用户手测清单。

由于正确功能位于另一条有未提交工作的分支，下一步需明确是在 `site-tz-plus` 接入，还是先将该功能合入当前 `debug-features` 工作树。当前没有合并分支或修改另一工作树。
