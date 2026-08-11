# Site 入口 Gateway 待同步状态实施总结

## 完成范围

- `SiteEntryTimeZoneSyncOverlay.State` 新增 `gatewaysNeedSync(SiteEntryTimeZoneResult)`。
- `showResult(_:)` 在 Gateway 汇总为 `.pending` 时自动进入新状态；`.noGateways` 和 `.inSync` 保持普通 `result`。
- 新状态复用现有 343 × 296 pt 结果卡，并对齐 Figma 节点 `399:11362`：Gateway 行使用 `#E17100` 警告色、10% 同色圆形底和 Figma 导出的 16 × 16 pt 警告 SVG。
- Footer 在新状态显示等宽 `LATER` 与 `REVIEW SYNC`，普通结果仍只显示 `GOT IT`，检查态仍不可关闭。
- 新增 English 与简体中文国际化 Key：`site_entry_sync_later`、`site_entry_sync_review_sync`。

## 交互结果

- 点击 `LATER`：`SiteViewController` 调用现有 `finishEntrySyncOverlay()`，取消任务、关闭 Overlay、解除返回锁定并继续既有入口导航。
- 点击 `REVIEW SYNC`：进入独立的 `handleEntrySyncReview()` Controller 扩展点，当前先调用 `finishEntrySyncOverlay()` 完成同样的关闭流程。
- 本次没有实现 Review 后续页面或 Gateway 同步业务，也没有发送 Gateway、BLE 或 Mesh 指令。

## TDD 记录

- RED 1：新增契约首次失败于缺少 `gatewaysNeedSync` 状态。
- RED 2：Overlay、资源和国际化实现后，契约失败点推进到 Controller 未绑定新回调。
- GREEN：绑定 `onLater` 与 `onReviewSync` 后，`SiteEntryTimeZoneSyncContractTests` 通过。
- 契约覆盖 `.pending` 状态选择、三组按钮互斥显示、警告资源、国际化、两条不同 Controller 回调路径及 Review 必须经过关闭流程。

## 验证结果

- `SiteEntryTimeZoneSyncPolicyTests`：通过。
- `SiteEntryTimeZoneSyncCoordinatorTests`：通过。
- `SiteEntryTimeZoneSyncContractTests`：通过。
- 警告 imageset JSON：`jq empty` 通过。
- 警告 SVG：`xmllint --noout` 通过；确认 `viewBox="0 0 16 16"` 和 `#E17100`。
- `git diff --check`：通过。
- generic iPhoneOS Debug、`CODE_SIGNING_ALLOWED=NO`：
  - `SunSmart`：`BUILD SUCCEEDED`。
  - `Archipelago`：`BUILD SUCCEEDED`。
  - `SLG Sync Plus`：`BUILD SUCCEEDED`。
  - `SylSmart`：`BUILD SUCCEEDED`。
- 四个构建均由 `actool` 处理共用 `SunSmart/Assets.xcassets`，证明新资源没有破坏各品牌 target 的 Asset Catalog 编译。

## 验证工具说明

当前环境的 `plutil -lint` 会把 Asset Catalog 的标准 JSON 当作 plist 解析，对新资源和项目既有 `site_entry_sync_success.imageset/Contents.json` 均报相同的首字符 `{` 错误。因此未把该结果视为资源缺陷，改用 JSON 专用解析器、XML 解析器和四个 target 的 `actool` 编译验证。

## 尚未验证

- 未进行真机视觉对照、触摸、Dynamic Type、旋转、弹窗动画或 VoiceOver 验收。
- 未实现、未验证 `REVIEW SYNC` 后续导航和 Gateway 时区同步业务。
- 未进行真实服务器、BLE 或 Mesh 设备验收。

## Git 状态

- 未创建 commit，未 push，未 merge。
