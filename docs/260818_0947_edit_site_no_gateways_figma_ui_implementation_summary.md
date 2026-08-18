# Edit Site 无 Gateway 状态 UI 实施总结

## 结果

已按 Figma `Content/GatewaysNoGateways` 更新 Edit Site 修改 Time Zone 后的 `No gateways` 空状态。

业务状态边界保持不变：

- 只有可配置 Gateway 集合为空时显示 `No gateways`。
- 存在 Gateway、但时区已经一致时，继续显示对应 Gateway 的 `Synced` 行。
- Gateway 检查不可用时继续显示 `Unable to check gateways`，不会降级为空状态。
- Site 保存、Gateway 权限筛选、Cloud API、轮询、超时和 `DONE` 行为未修改。

## UI 改动

- 将原来的 152pt 居中纵向空状态改为约 89pt 的紧凑行式卡片。
- 增加独立 `GATEWAYS` Header，使用 12pt Regular 和现有次级文字颜色。
- 增加 32pt、10% 灰色背景的圆形图标底座。
- 复用现有 `time-zone-sync-status-gateway` SVG，以 16pt 原始渐变样式显示，不再强制黄色 Tint。
- `No gateways` 与辅助说明改为右侧两行左对齐布局，间距和颜色按 Figma 设置。
- 移除空状态 152pt 最小高度，通过 Auto Layout 和 `systemLayoutSizeFitting` 自然测量；Dynamic Type 或窄宽度换行时可自动增高，并继续通知父结果 Sheet 更新高度。
- VoiceOver 将 `GATEWAYS` 作为 Header，将空状态两行文案合并朗读一次，图标保持装饰性。

## 国际化与资源

- 复用 `site_no_gateways` 和 `site_no_gateways_sync_needed`。
- English 文案保持 Figma 的长破折号：`No gateways configured — no sync needed.`。
- 现有 English 和简体中文翻译已完整，无需修改 `Localizable.strings`。
- 现有 SVG 与 Figma 导出图标的路径、渐变一致，无需新增 Asset Catalog 内容或修改 target 配置。

## 修改文件

- `SunSmart/Main/Site/View/SiteEntryGatewayTimeZoneStatusView.swift`
- `Tests/Site/SiteGatewayCloudTimeZoneUIContractTests.swift`
- `docs/260818_0939_edit_site_no_gateways_figma_ui_plan.md`
- `docs/260818_0947_edit_site_no_gateways_figma_ui_implementation_summary.md`

## 验证结果

- 新 UI contract 在生产代码修改前按预期 RED，实施后转为 GREEN。
- 完整 `scripts/check_site_sync_gateways.sh`：通过，最终输出 `SiteSyncGateways checks passed`。
- `git diff --check`：通过。
- generic iPhoneOS Debug unsigned 构建：
  - `SunSmart`：`BUILD SUCCEEDED`
  - `Archipelago`：`BUILD SUCCEEDED`
  - `SLG Sync Plus`：`BUILD SUCCEEDED`
  - `SylSmart`：`BUILD SUCCEEDED`

## 未覆盖范围

- 真机视觉与 Figma 像素级验收。
- VoiceOver 和系统 Dynamic Type 的真机交互验收。
- 真实服务器、Gateway、BLE/Mesh 下发与超时行为。

本次静态契约与 unsigned build 证明源码约束和四品牌编译通过，不代表上述端到端行为已经验证。
