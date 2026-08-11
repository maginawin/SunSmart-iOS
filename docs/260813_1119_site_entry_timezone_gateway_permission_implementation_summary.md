# Site Entry Time Zone 与 Gateway 权限状态实施总结

## 实施结论

已完成进入 Site 页面时的 Site timezone 仲裁与 Gateway `timezoneOffset` 状态检查，并保持每个 `SiteViewController` 实例只消费首次成功响应。

本期只负责生成并展示 `Sync status`：当存在待同步 Gateway 时，`REVIEW SYNC` 仍只关闭弹窗，不执行后续导航、扫描、BLE/Mesh 或 Gateway 写入。

## 已实现业务

### Owner

- 使用 cloud/app Site 的 `updateTimestamp` 仲裁目标 timezone；cloud 较新时更新本地，其他冲突情况由 app timezone 更新 cloud。
- 检查响应中的全部 Gateway，并按规范将 `timezoneOffset` 通过 `(value - 64) × 15` 转为 UTC Offset 分钟。
- Site timezone 已一致但存在待同步 Gateway 时，Site 行显示 `Already in sync with server`，弹窗进入 `gatewaysNeedSync` 状态。
- Gateway 缺少或包含非法 `timezoneOffset` 时计为待同步。

### 拥有 Editor Spaces 的用户

- Site timezone 仲裁规则与 Owner 相同。
- 仅检查 Editor Spaces 的 `gatewayId` 所绑定的 Gateway；Visitor Spaces 的 Gateway 不参与统计。
- 同一个 Gateway 被多个 Editor Spaces 绑定时按 Gateway ID 去重。
- Editor Space 绑定了 Gateway，但响应中缺少对应 Gateway 对象时，计为待同步。

### 仅拥有 Visitor Spaces 的用户

- 始终以 cloud 返回的完整 Site props 为准，不允许 app 数据反向更新 cloud。
- 本地同步 `siteName`、`imageId`、`timezone` 和 cloud `updateTimestamp`。
- `lastUpdate` 与 `lastUploadCloudTimestamp` 均收敛为 cloud `updateTimestamp`，并清除 Site props pending 状态，避免无权限的本地数据继续表现为更新版本。
- 不检查 Gateway，不显示 `Sync status`，不发起 Site props 上传。

### 通用边界

- 没有权限范围内 Gateway 时，只结束 Gateway 检查分支；如果 Site timezone 本身发生更新，仍展示 `Updated from server` 或 `Updated to server` 结果。
- Site timezone 与目标 Offset 一致的 Gateway 显示已同步；缺失、非法或 Offset 不一致的 Gateway 进入待同步数量。
- `timezoneOffset` 支持整数、可无损转换为整数的 `NSNumber` 和数字字符串；Bool、非整数、越界值均视为非法。

## 主要改动

- Response Parser：解析完整 Site props、Space 权限与绑定 Gateway ID、Gateway ID 与 timezone Offset，并统一规范化 Gateway ID。
- Policy：集中处理 Owner、Editor、Visitor 权限范围、Site timezone 仲裁和 Gateway 待同步统计。
- Coordinator：新增 Gateway-only 的 `Already in sync with server` 结果，以及 Visitor cloud 权威状态的静默落库路径。
- Site 页面：在完整数据导入完成后分流可见弹窗、Visitor 静默更新或正常导航，并保留首次成功响应消费约束。
- Overlay 与国际化：新增 English `Already in sync with server` 和简体中文 `已与服务器同步`。
- 测试：扩展 Policy、Coordinator 和 UI/生命周期契约，覆盖权限矩阵、非法 Offset、缺失 Gateway、Visitor 收敛及本地化。

## TDD 与验证证据

实现前已分别确认以下 RED：

- Parser/Policy 因缺少 Space/Gateway 快照与权限决策接口而失败。
- Coordinator 因新决策未穷尽并缺少 Visitor 静默路径而失败。
- UI 契约因缺少 `Already in sync with server` 本地化与消费分支而失败。

最终验证结果：

| 验证项 | 结果 |
| --- | --- |
| `SiteEntryTimeZoneSyncPolicyTests` | Passed |
| `SiteEntryTimeZoneSyncCoordinatorTests` | Passed |
| `SiteEntryTimeZoneSyncContractTests` | Passed |
| `SitePropsEditPolicyTests` | Passed |
| `SiteTimeZonePersistenceContractTests` | Passed |
| `SitePropsAPIContractTests` | Passed |
| `SiteTimeZoneUIContractTests` 两种入口 | Passed |
| `SiteUpdateToastUIContractTests` component/routing | Passed |
| `SiteEditAlertTransitionContractTests` component/edit-site | Passed |
| English 与简体中文 strings `plutil -lint` | OK |
| `git diff --check` | Passed |
| 新流程 Gateway/BLE/Mesh 写入与 Review 路由静态扫描 | 无匹配 |
| `SunSmart` generic iPhoneOS build | BUILD SUCCEEDED |
| `Archipelago` generic iPhoneOS build | BUILD SUCCEEDED |
| `SLG Sync Plus` generic iPhoneOS build | BUILD SUCCEEDED |
| `SylSmart` generic iPhoneOS build | BUILD SUCCEEDED |

## 尚未验证

- Editor Space 用户调用 Site props update API 时，真实服务器是否允许更新 Site timezone。
- 真实 `/sitespace/get/siteprops` 响应是否在所有账号与历史数据场景都提供完整的 Site、Space、Gateway 字段。
- 真机上的弹窗视觉、按钮交互与首次进入时序。
- 真实 Gateway、BLE 与 Mesh 同步；本期没有实现这些操作。

## 工作区状态

实现保留在当前 `time-zone` worktree 中，未执行 commit、push 或 merge。
