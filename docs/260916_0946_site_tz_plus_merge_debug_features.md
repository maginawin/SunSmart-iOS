# site-tz-plus 合并到 debug-features

## 合并结果

- `debug-features` 从 `cf5e5c13` 快进至本地 `site-tz-plus` 的 `e32ef78f`（同步错误与大规模节点 CPU 修复）。
- 执行 `git merge --ff-only --autostash site-tz-plus`，合并和恢复本地改动均无冲突，因此没有需要确认的冲突修复方案。
- 原有工作区内容保持未提交；未创建额外合并提交，未推送远端，未修改来源分支。
- 合并前 14 个已修改或未跟踪文件已备份至 `/tmp/debug-features-before-site-tz-merge-260916_094523`，包含 SHA-256 清单、原始差异及合并前 HEAD。
- 其中 12 个文件逐字节未变；Site 页面原有功能可见性补丁完整保留，另叠加来源分支的两处错误提示调整；工程文件通过结构化比较，完整保留双方对象和引用。

## 验证结果

- 功能开关检查脚本通过：Debug/Release 可见性矩阵、真实 Site 菜单方法、角色变更、过期点击和权限检查。
- 五个品牌 target 均仅包含一份 FeatureVisibility.swift 与 debug_features.json，来源分支新增的 8 个 Swift 文件在每个 target 均仅引用一次。
- 新增 configuration_reload_invalid 国际化键在英文、简体中文中均存在且无重复。
- 工程文件 plutil 检查、git diff --check 通过；无未解决冲突，HEAD 与 site-tz-plus 一致。
- 直接运行 xcodebuild，SunSmart Debug iPhoneOS 构建成功，使用 generic/platform=iOS 和 CODE_SIGNING_ALLOWED=NO，未使用 Simulator。

## 验证边界

本次仅执行分支集成，没有新增冲突修复或 UI 实现。其他品牌只检查工程引用，未逐一构建；未执行真机 UI、硬件同步或性能验收。人工回归可检查 Site Trigger Zone 入口随角色和 Debug/Release 配置变化、大规模 Space 页面切换及同步状态刷新。构建成功不代表 UI 或性能验收通过。
