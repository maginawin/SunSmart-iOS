# Time Zone Sync Final Review Fixes Plan

## 背景

最终代码审查确认当前方案无 Critical，但有两项必须在完成前修复的 Important：

1. Edit flow 的 `SiteTimeZoneRemoteSnapshotProvider` 直接复用宽松 Entry parser。缺失/错误类型的 `role`、`spaces`、`gateways` 或畸形条目可能被降级为 Visitor/空数组/部分数组，从而把不完整快照误报为 `No gateways` 或只同步解析成功的子集，违反 fail-closed 约束。
2. 统一状态视图虽然使用 Dynamic Type 字体，但 checking、标题、Site card 与结果高度公式仍依赖固定高度，Accessibility 字号可能裁切。

## Fix 1：严格完整快照边界

- 保留既有 Entry parser 的兼容行为，避免扩大 Site entry/import 回归范围。
- 在 Edit provider 路径增加独立严格解析/验证边界：
  - Site role 必须是受支持的明确值。
  - `spaces` 与 `gateways` 必须存在且容器类型正确。
  - 每个 Space/Gateway 的权限与目标识别必要字段必须类型合法；不得丢弃畸形子项后继续同步剩余子集。
  - timezone、Site 基础字段仍由既有 parser 验证；任一严格条件失败返回 `.unavailable`。
- 先新增行为测试，覆盖缺 key、错误容器类型、未知 role、畸形条目；确认 RED 后实现最小 strict boundary。
- 确认 Edit coordinator 对 `.unavailable` 继续发布 Gateway `.unavailable` 且 Gateway API 调用数为 0。

## Fix 2：统一状态 View 的 Dynamic Type 自适应

- checking card、标题、Site card 的文字区域改为 intrinsic/minimum height；不依赖固定单行高度裁切字体。
- 结果 Sheet 的固定内容高度从实际 Auto Layout 测量或统一可更新约束获得；Gateway viewport 继续使用剩余 safe-area 空间。
- `traitCollectionDidChange` 在 content size category 变化时重新测量与更新结果布局。
- 保留全宽 Sheet、底部 safe area 白色、61pt terminal Footer、Pushing 时 Footer 0、DONE 位置和不可提前关闭语义。
- 先扩展 UI contract/布局测试确认 RED，再实现并复跑。

### Fix 2 审查补充

首次自适应实现仍把 Gateway `minimumViewportHeight` 作为硬下限；在小屏、Accessibility 字号与 Failed 终态组合下，结果卡会被 safe-area 最大高度压缩，但 Footer 位于 Gateway 之后且结果卡裁剪内容，可能使唯一 `DONE` 不可见。修正方案：

- 结果标题、Site card、Gateway 区进入可滚动内容区域。
- 61pt terminal Footer 固定在结果卡可视底部，不随内容滚出或被 Gateway 最小高度推走；Pushing 时 Footer 仍折叠为 0。
- 结果卡默认内容未超限时保持当前紧凑高度；超限时卡高限制在 safe area，内容区滚动。
- Gateway 使用可测量的内容高度，不再用硬最小 viewport 推高整个结果卡；极端尺寸由外层结果内容滚动承接。

### Fix 2b 审查补充

- `.notStarted` 父 View 高度为 0 时，Gateway 子 View 必须停用 Empty/Gateway/Failure 的 top-bottom 展示链并隐藏内部内容，避免与 Empty `height >= 152` 的 required 约束冲突；下一次 `.batch/.unavailable` 再恢复对应链。
- 复用的 Site status view 在进入新 `.working` 会话时把 outer scroll offset 归零；Pushing 到 terminal 的同一会话不得归零，以保留连续阅读位置。

## 验证与审查

- 每项修复完成后运行对应 focused test、完整 `./scripts/check_site_sync_gateways.sh` 与 `git diff --check`，并进行独立只读审查。
- 两项均通过后，运行两份 Localizable、project lint、关联 Site contracts，并严格串行重跑 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 generic iPhoneOS build。
- 静态、contracts 与编译不替代真实服务器、真机 lifecycle、VoiceOver/Dynamic Type、BLE/Mesh 或 Figma 像素验收。
