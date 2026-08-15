# Time Zone 同步流程收敛实施总结

## 实施结果

方案 A 已完成：`SiteTimeZoneSyncStatusView` 现在统一承载 Site 页面进入、Sites 页面 Edit Site、Site 页面 Edit Site 三个入口的 Time Zone 同步进度与结果展示，旧的 `SiteEntryTimeZoneSyncOverlay` 已删除。

统一流程会先确认 Site Time Zone 更新结果，再基于可信的完整远端快照判断 Gateway 是否需要更新。需要更新时展示 `Pushing...`、`Synced`、`Failed`；不需要更新时展示无待同步 Gateway 的结果。离线编辑只保留本地待同步状态，不提前构造或展示 Gateway 同步流程。

## UI 与状态行为

- 状态视图宽度跟随当前 ViewController 或容器，不保留左右间隔。
- 底部 safe area 使用白色背景，`DONE` 固定在结果卡片底部。
- Gateway 行的状态图标统一位于左侧：加载、成功、失败图标替换原 Gateway 图标；右侧只保留状态文字。
- `Pushing...` 的加载动画继续运行，并在状态切换、复用或清空时正确停止。
- 结果内容支持 Dynamic Type；内容超出可用高度时由滚动区域承载，固定 Footer 和 `DONE` 不被裁切。
- `.notStarted`、批量结果、不可用状态之间切换时会停用旧约束和旧动画；新同步会话开始时重置滚动位置。

## 数据与权限边界

- Edit Site 使用严格远端快照解析：Site role、Spaces、Gateways、Gateway identity 与 timezoneOffset 任一结构不完整或类型非法时，整份快照判定为不可用，不把异常数据误判为 `No gateways`。
- Entry 原有解析边界保持不变。
- Owner、Editor、Visitor 的授权范围继续由既有 permission scope 与 Gateway target policy 决定。
- Sites 入口在终态仅刷新对应 Site；Site 入口在终态同步本地确认 offset、Review 状态并执行静默 reconcile。

## 自动化验证

- `./scripts/check_site_sync_gateways.sh`：通过，包含共享 session、Edit coordinator、严格快照 parser、状态展示和布局 policy 等检查。
- SiteProps edit/API/API response parser/timezone persistence contracts：通过。
- Toast component/routing 与 Edit alert component/edit-site contracts：通过。
- English、简体中文 Localizable 及 `project.pbxproj` plist 检查：通过。
- `SiteEntryTimeZoneSyncOverlay` 在 `SunSmart`、工程配置、脚本和测试活动范围内零引用。
- `git diff --check`：通过。
- 独立最终代码审查：无 Critical 或 Important 遗留。

## 构建验证

以下四个 scheme 均以 Debug、generic iPhoneOS、关闭代码签名方式直接运行 `xcodebuild`，结果均为 `BUILD SUCCEEDED`：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

构建中仍存在工程既有的 Info.plist Copy Resources、重复资源或资源符号、旧 API 以及无 AppIntents 依赖等警告；本次改动未新增编译错误。

## 尚需人工验收

- 使用真实服务器 payload 验证完整快照与 Owner、Editor、Visitor 权限组合。
- 使用真机验证进入 Site、两个 Edit Site 入口的生命周期、取消和晚到回调。
- 使用真机验证 Dynamic Type、VoiceOver、嵌套滚动和底部 safe area。
- 验证真实 Gateway/BLE/Mesh 的 Time Zone 最终写入与回读。
- 对照 Figma 完成像素级视觉验收。

## 工作区状态

实现保留为未提交改动。本轮未执行 `git add`、`git commit`、`git push`、`git merge`、`git reset` 或 `git clean`。
