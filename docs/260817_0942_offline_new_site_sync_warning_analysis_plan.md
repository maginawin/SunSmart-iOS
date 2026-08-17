# 离线新建 Site 未显示同步提示：原因分析与修复规划

> 本方案已被 `docs/260817_0954_offline_new_site_timezone_pending_revised_plan.md` 取代。原方案把整 Site dirty 状态直接并入时区提示，扩大了 `Not synced to server` 的语义，不再建议实施。

## 1. 问题结论

问题不是新建 Site 没有保存手机本地时区，也不是整 Site 上传遗漏了 `timezone` 字段，而是 Edit Site 页面只观察了其中一套“未同步”状态。

当前工程存在两套职责不同的本地同步状态：

| 状态来源 | 表示的业务 | 建立方式 | 成功后清理方式 |
|---|---|---|---|
| `SiteData.needUploadCloud` | 整 Site 数据尚未由整包同步确认 | `lastUpdate > lastUploadCloudTimestamp`，新建 Site 的 `lastUploadCloudTimestamp` 为 `nil` | `CloudSynchronizationManager` 的 `.syncSite` 成功后推进 `lastUploadCloudTimestamp` |
| `pendingSitePropsMask` | Edit Site 的 name、imageId、timezone 字段尚未由 Site Props API 确认 | `SitePropsEditCoordinator` 保存离线编辑或失败重试状态 | Site Props update 成功，或后续 retrieve 对账成功后按字段清理 |

`Not synced to server` 当前仅由 `pendingSitePropsMask` 控制，因此漏掉了“整 Site 尚未上传”的新建 Site。

## 2. 源码状态链

### 2.1 离线新建 Site

1. `SitesViewController.addSite()` 调用 `SiteData.add(name:)`。
2. `SiteData.add(name:)` 创建本地 Site，并在首次 `save()` 前把 `SiteTimeZoneCatalog.phoneDefaultValue()` 写入 `site.timezone`。
3. 新对象的 `lastUpdate` 等于创建时间，`lastUploadCloudTimestamp` 默认为 `nil`，所以 `site.needUploadCloud == true`。
4. 新对象的 `pendingSitePropsMask` 使用默认空值，因为这不是一次 Edit Site 字段提交。
5. 页面随后 enqueue `.syncSite(site:)`；离线时服务器没有确认成功，`lastUploadCloudTimestamp` 不会推进，因此整 Site 继续保持待上传。
6. 重新进入 Edit Site 时，离线路径直接从本地 Site 构造 draft。
7. `SiteEditViewController.updatePendingDisplay()` 只判断 `site.pendingSitePropsMask.isEmpty`。此时 mask 为空，所以隐藏提示，尽管 `site.needUploadCloud` 为 true。

### 2.2 离线编辑时区

1. 用户选择了不同 timezone 后，`SitePropsEditPolicy.changedFields` 产生 `.timezone`。
2. `SitePropsEditCoordinator.makeCommitPlan` 将变化字段与历史 pending 合并，并生成严格推进的 timestamp。
3. 离线保存会持久化 timezone、`lastUpdate`、`.timezone` pending 和 pending timestamp，但不会创建网络 snapshot。
4. 再次进入 Edit Site 时 `pendingSitePropsMask` 非空，因此当前 UI 能显示 `Not synced to server`。

这解释了两个场景的表面差异：二者都未同步，但分别由整 Site dirty 状态和 Edit Site props pending 状态表达；UI 只读取了后者。

## 3. 修复原则

推荐把提示定义为两个状态的并集：

- Edit Site 字段存在 pending；或
- Site 整包数据仍需要上传，即 `site.needUploadCloud == true`。

不建议在 `SiteData.add(name:)` 中人为写入 `.timezone` pending，原因如下：

- 新建 Site 已由 `.syncSite` 整包上传，且导出内容已经包含有效 timezone；再建立 Site Props pending 会让同一数据同时进入两套上传协议。
- 整包同步成功回调按设计不清理 `pendingSitePropsMask`。强行清理还必须处理“整包请求在途期间又发生 Edit Site 修改”的竞态，否则可能误清较新的字段 pending。
- 现有 `lastUploadCloudTimestamp` 已能准确表达服务器是否确认了新 Site，无需新增持久化字段或第二套版本。

## 4. 推荐修复方案

### 4.1 统一提示的显示判定

在 `SiteEditViewController` 内集中定义 Edit Site 的未同步提示状态，输入为：

- `!site.pendingSitePropsMask.isEmpty`
- `site.needUploadCloud`

任一为 true 时显示 `Not synced to server`；两者均为 false 时隐藏。

该改动同时覆盖从 Sites 列表和 Site 内页进入 Edit Site 的入口，因为两个入口共用同一个 `SiteEditViewController`。

### 4.2 保持同步职责不变

- 新建 Site 继续由 `CloudSynchronizationManager.syncSite` 使用整包 Site Add/Upload 接口同步。
- 离线编辑 timezone/name/imageId 继续由 `SitePropsEditCoordinator` 和 Site Props API 重试。
- 不修改 `SiteData.add` 的默认 timezone 初始化。
- 不让 `CloudSynchronizationManager` 读写 `pendingSitePropsMask`。
- 不修改服务器请求结构、timestamp 仲裁、Gateway/Mesh TimeSet 或权限逻辑。

### 4.3 页面生命周期

首次进入页面仍在 `viewDidLoad` 更新提示。为避免 Site 整包同步在页面存活期间完成后提示仍显示旧状态，可在页面重新可见时复用同一更新方法刷新一次；不新增通知或观察者。

### 4.4 点击行为边界

本问题只调整提示的可见性。`Not synced to server` 与 DONE 共用提交入口的现有行为保持不变：

- 存在 Site Props pending 时，继续执行原有字段重试流程。
- 仅存在整 Site dirty、且用户没有编辑任何字段时，不把它转换为 Site Props update，也不在 Edit Site 内新增第二条整 Site同步链路。
- 整 Site 的联网自动重试继续由现有 Sites 加载和 `CloudSynchronizationManager` 负责。

如果产品后续要求点击该提示必须立即重试“创建 Site”，需要单独设计整 Site同步状态、进行中/失败反馈和重复请求合并；不应混入本次显示缺陷。

## 5. 预计改动范围

- 修改：`SunSmart/Main/Site/Controller/SiteEditViewController.swift`
  - 合并 `pendingSitePropsMask` 与 `needUploadCloud` 两个显示来源。
  - 在合适的可见生命周期刷新同一判定。
- 修改：`Tests/Site/SiteTimeZoneUIContractTests.swift`
  - 更新现有仅检查 `pendingSitePropsMask.isEmpty` 的 UI contract。
  - 固定两个状态来源的并集语义。
- 可选增强：`Tests/Site/SiteTimeZonePersistenceContractTests.swift`
  - 明确新建 Site 使用手机默认 timezone，但不伪造 Edit Site pending；整 Site上传状态仍由 upload timestamp 表达。

不需要修改本地化、资源、target 配置或 SDK。

## 6. 测试矩阵

| 场景 | `pendingSitePropsMask` | `needUploadCloud` | 预期提示 |
|---|---:|---:|---|
| 离线新建 Site，首次整包上传未成功 | 空 | true | 显示 |
| 新建 Site 整包上传成功 | 空 | false | 隐藏 |
| 已上传 Site，离线编辑 timezone | `.timezone` | true | 显示 |
| 已上传 Site，字段 pending 尚未对账，但整包 timestamp 已推进 | 非空 | false | 显示 |
| 已上传且无本地待同步数据 | 空 | false | 隐藏 |

实现后建议验证：

1. 运行 `SiteTimeZoneUIContractTests`、`SiteTimeZonePersistenceContractTests`、`SitePropsEditPolicyTests` 和 `SitePropsAPIContractTests`。
2. 运行 `git diff --check`。
3. 按工程规则依次执行 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 generic iPhoneOS Debug、`CODE_SIGNING_ALLOWED=NO` 构建。
4. 真机手工验证离线新建、离线编辑 timezone、恢复网络后整 Site 上传成功再重入，以及 App 重启后的持久化表现。

自动 contract 和构建只能证明静态接线与编译成立；服务器是否真实收到 Site Add、网络恢复重试和 UI 最终消失仍需真实网络/服务器验收。

## 7. 当前工作区边界

分析开始时已有以下未提交改动，本方案不触碰：

- `SunSmart/Assets.xcassets/Common/site_entry_sync_warning_target.imageset/`
- `SunSmart/Main/Site/View/SyncGatewaysSupportingViews.swift`
