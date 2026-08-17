# 离线新建 Site Timezone Pending：重新分析与修复规划

## 1. 修正结论

上一版方案不合适。Edit Site 中的 `Not synced to server` 位于 Time Zone 标题右侧，点击后进入 `Update Site time zone` 确认或离线提示流程，它应表达“timezone 尚未同步”，不能直接使用整个 Site 的 `needUploadCloud`。

本次修复不能只在“创建 timezone pending”和“UI 过滤 timezone pending”之间二选一，两个动作都需要：

1. 新建 Site 写入手机默认 timezone 时，同时建立 `.timezone` pending，才能表达这个默认值尚未被服务器确认。
2. Edit Site 的提示只检查 `pendingSitePropsMask.contains(.timezone)`，避免 name、imageId 或其他整 Site dirty 状态误触发时区提示。

此外，需要处理首次 Site Add 成功后的 pending 收敛，否则可能出现服务器已经接受 timezone，但用户随后离线进入 Edit Site 仍看到陈旧提示。

## 2. 当前行为与问题

### 2.1 当前提示判定本身已经过宽

`SiteEditViewController.updatePendingDisplay()` 当前使用 `site.pendingSitePropsMask.isEmpty`：

- `.timezone` pending 会显示提示，符合交互语义。
- 仅 `.siteName` pending 也会显示提示，但点击后不会进入 timezone 更新流程。
- 仅 `.imageId` pending 同样会显示提示。

因此，无论是否处理新建 Site，提示判定都应该收窄为只观察 `.timezone`。

### 2.2 只过滤 `.timezone` 不能修复新建 Site

`SiteData.add(name:)` 当前会：

1. 创建 Site，`lastUpdate` 使用创建时间；
2. 写入 `SiteTimeZoneCatalog.phoneDefaultValue().storageValue`；
3. 首次保存；
4. 保持 `pendingSitePropsMask == []`、`pendingSitePropsTimestamp == nil`。

如果 UI 改成只检查 `.timezone`，新建 Site 的 mask 仍为空，原问题会继续存在。

### 2.3 只创建 `.timezone` pending 也不完整

如果只在新建 Site 时写入 `.timezone` pending，而 UI 继续检查 mask 是否为空，name/imageId pending 仍会错误显示时区提示。

同时，新建 Site 仍通过 `.syncSite` 的 Site Add 整包接口上传，payload 已包含 timezone。当前整包同步成功只推进 `lastUploadCloudTimestamp`，不会清理 Site Props pending。虽然下一次在线进入 Edit Site 时，`prepareDraft` 的 retrieve 可以按 timestamp 和字段值对账清理，但存在一个陈旧状态窗口：

1. Site Add 已成功；
2. 用户还没有在线进入过 Edit Site，因此 pending 尚未 retrieve 对账；
3. 用户转为离线后进入 Edit Site；
4. 页面仍会显示 `Not synced to server`，但服务器实际上已经收到 timezone。

因此，推荐让首次 Site Add 成功对“本次实际提交的默认 timezone”做一次带版本保护的即时对账。

## 3. 推荐方案

### 3.1 新建 Site 建立 timezone pending

在 `SiteData.add(name:)` 中，写入默认 timezone 后、首次 `save()` 前同步写入：

- pending mask：仅 `.timezone`
- pending timestamp：使用该 Site 已有的 `lastUpdate`

这样 timezone 值、Site 版本和 pending 版本来自同一个创建快照，App 重启后也能恢复。

不要使用新的 timestamp，也不要新增专用布尔字段或第二套版本号。

### 3.2 UI 只显示 timezone pending

`SiteEditViewController.updatePendingDisplay()` 只根据 `pendingSitePropsMask.contains(.timezone)` 控制显示。

明确排除：

- 仅 `.siteName` pending；
- 仅 `.imageId` pending；
- `site.needUploadCloud`；
- `site.uploadCloud == false`；
- Space、Gateway 或其他整 Site同步状态。

DONE 按钮仍处理所有 pending 字段；这里只收窄 Time Zone 标题右侧提示的可见语义。

### 3.3 首次 Site Add 成功时安全收敛创建 pending

不应在成功回调中直接按当前 Site 值无条件清理 pending，因为 Site Add 请求在途期间，用户可能再次修改 timezone。

推荐在生成首次 `.siteAdd` 请求后，从已经冻结的请求 payload 建立只读提交快照：

- Site ID
- 本次提交的 `updateTimestamp`
- 本次提交的 timezone

Site Add 成功后，仅当以下条件全部成立时清除 `.timezone` pending：

1. 当前 pending 仍包含 `.timezone`；
2. 当前 `pendingSitePropsTimestamp` 等于本次提交的 `updateTimestamp`；
3. 当前本地 timezone 等于本次实际提交的 timezone。

清除后：

- 如果没有其他 pending 字段，同时清空 pending timestamp；
- 如果仍有 name/imageId pending，只移除 `.timezone`，保留原 timestamp；
- 任一条件不匹配时不清理，保留用户在请求期间产生的新版本。

`lastUploadCloudTimestamp` 也应推进到“本次实际提交的 updateTimestamp”，而不是响应到达时 Site 对象的最新 `lastUpdate`。否则请求期间的新编辑可能被误标为已经整包上传。若本地已有新版本，`lastUpdate` 会继续大于本次确认值，现有 `needUploadCloud` 仍能表达需要后续整包上传。

这个清理只适用于首次 `.siteAdd` 的创建快照，不扩展为所有 `.siteUpload` 成功都清理 Site Props pending，避免改变既有两套同步链路的总体边界。

### 3.4 保留既有 Site Props 重试与 retrieve 对账

- Site Add 失败或无网络：不清 pending，离线重入 Edit Site 会显示提示。
- 用户在 Site Add 请求期间修改 timezone：版本或值不匹配，不清 pending。
- 普通 Edit Site timezone 更新：继续由 `SitePropsEditCoordinator` 和 `/sitespace/update/siteprops` 处理。
- 其他整包 Site Upload 恰好上传了 pending 字段：继续沿用既有“下次在线进入 Edit Site 后 retrieve 对账”规则。

## 4. 为什么不推荐其他方案

### 4.1 只使用 `site.needUploadCloud`

会把非 timezone 的整 Site 变化也映射到 Time Zone 提示，正是上一版方案的问题。

### 4.2 只检查 `pendingSitePropsMask.contains(.timezone)`

当前新建 Site 没有 `.timezone` pending，因此无法修复报告场景。

### 4.3 创建 pending，但完全依赖下次 retrieve 清理

能修复最初的离线显示，但首次 Site Add 成功后仍可能保留陈旧 pending，直到下一次在线进入 Edit Site；在此之前离线进入会误报。

### 4.4 Site Add 成功后无条件移除 `.timezone`

可能清掉请求期间用户刚产生的新 timezone 版本，属于真实竞态。必须使用提交 timestamp 和提交值双重匹配。

## 5. 克隆 Site 边界

当前已确认设计和 contract 要求克隆 Site 重置 pending，因此本次只修改 `SiteData.add(name:)` 的普通新建流程，不修改 `cloneData()`。

如果产品认为克隆出来的新 Site 也应把继承或默认生成的 timezone 标记为未同步，需要单独调整既有 clone contract；不在本次需求中默认扩大。

## 6. 预计改动范围

- 修改：`SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
  - 新建 Site 首次保存前建立 `.timezone` pending 和同版本 timestamp。
- 修改：`SunSmart/Main/Site/Controller/SiteEditViewController.swift`
  - 提示只检查 `.timezone` pending。
- 修改：`SunSmart/Common/Cloud/CloudSynchronizationManager.swift`
  - 仅为首次 Site Add 捕获不可变 timezone 提交快照。
  - 成功时按 timestamp 和 timezone 值安全移除创建 pending。
  - 用已提交 generation 推进 `lastUploadCloudTimestamp`。
- 修改：`SunSmart/Main/Site/Model/SitePropsEditPolicy.swift` 或新增同目录纯策略类型
  - 承载并测试 Site Add 成功后的纯对账规则，避免在网络回调中散落条件。
- 修改相关测试：
  - `Tests/Site/SiteTimeZonePersistenceContractTests.swift`
  - `Tests/Site/SiteTimeZoneUIContractTests.swift`
  - `Tests/Site/SitePropsEditPolicyTests.swift`
  - `Tests/Site/SitePropsAPIContractTests.swift`

不需要修改本地化、资源、target 配置、Gateway/Mesh TimeSet 或 SDK。

## 7. 测试矩阵

### 7.1 提示可见性

| pending | 预期 |
|---|---|
| 空 | 隐藏 |
| 仅 `.siteName` | 隐藏 |
| 仅 `.imageId` | 隐藏 |
| `.siteName + .imageId` | 隐藏 |
| 仅 `.timezone` | 显示 |
| `.timezone` 与其他字段组合 | 显示 |

### 7.2 新建与 Site Add 对账

| 场景 | 预期 |
|---|---|
| 离线新建 Site | 默认 timezone 已保存，`.timezone` pending 已持久化，提示显示 |
| 首次 Site Add 失败 | pending 保留 |
| Site Add 成功，timestamp 与 timezone 都匹配 | 只清除 `.timezone` pending |
| Site Add 在途期间修改 timezone | 新 pending 保留 |
| Site Add 在途期间修改 name/imageId 并推进版本 | 不用旧提交清理新版本 |
| 清除 timezone 后仍有 name/imageId pending | 保留其他字段及 pending timestamp；时区提示隐藏 |
| Site Add 成功后再离线进入 Edit Site | 不显示陈旧 timezone 提示 |

### 7.3 回归验证

1. 运行 Site timezone persistence、UI、policy 和 API contracts。
2. 运行 `git diff --check`。
3. 依次执行 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 generic iPhoneOS Debug、`CODE_SIGNING_ALLOWED=NO` 构建。
4. 真机验证离线新建、离线重入、恢复网络后的首次 Site Add、请求在途再次编辑，以及 App 重启后的 pending 恢复。

自动 contract 和构建不能证明真实 Site Add/Props API、网络恢复、并发时序或 UI 交互，需要服务器与真机验收。

