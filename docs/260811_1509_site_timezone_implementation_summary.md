# Site Time Zone 实现与验证总结

## 完成范围

本次按已确认的设计与实施计划完成 Sites - Site options menu - Edit Site 的 Time Zone 功能，并在图标列表上方增加 Site Icon 标题。

实现边界保持如下：

- 仅 Edit Site 使用 `/sitespace/retrieve/siteprops` 和 `/sitespace/update/siteprops`。
- 原 `/sitespace/sync/siteprops` 整包同步流程保持不变，只在原 Site 数据中增加 timezone。
- 始终只维护一个 `site.lastUpdate`，Edit Site 更新时将其作为 `updateTimestamp`。
- 未新增第二套云端版本时间，也未新增整包同步选择标记。
- 未修改 `CloudSynchronizationManager`、通用 `InfoEditViewController`、Timed 和 Gateway Time Set。
- Gateway 同步仍不在本期范围，成功状态固定展示 No gateways。

## 主要实现

### 时区模型与目录

- 新增完整格式解析与规范化，格式为 `IANA (UTC±HH:mm)`。
- Local time 只使用 JSON 中的固定 UTC offset 计算，不使用 IANA 夏令时规则。
- Local time 显示格式为 `Local time · yyyy-M-d h:mm:ss a`，每 0.5 秒以新的当前时间刷新。
- 解析 `all_utc_timezones.json` 的 397 条数据，并在首部注入 UTC / Etc/UTC，最终为 9 个分组、398 条记录。
- 搜索会 trim 输入，并对 region、ianaId、原始 utcOffset 和展示 offset 做忽略大小写的模糊匹配。
- 新建 Site 默认使用手机当前时区；优先匹配目录静态 offset，无法匹配时使用手机时区的标准时偏回退。

### 数据与同步

- Site 本地数据库增加 timezone、pending 属性掩码和 pending 时间戳，并为旧数据库提供独立列迁移。
- 新建 Site、克隆 Site、整包导出和整包导入均处理 timezone。
- 服务器缺少 timezone、返回 null 或空字符串时保留本地 timezone；非空但格式无效时拒绝该次 retrieve 数据。
- retrieve 根据 `updateTimestamp` 与本地 `site.lastUpdate` 合并；请求失败时静默使用本地数据。
- update 只发送实际变化或待重试的 siteName、imageId、timezone，并始终发送 updateTimestamp。
- 更新回复严格校验时间戳和本次发送字段；失败状态会持久保留，重启后仍可从 Edit Site 重试。

### UI 与流程

- 使用专用 `SiteEditViewController`，页面标题继续显示 Site name。
- 页面顺序为 Name、Time Zone、Site Icon、图标列表。
- Time Zone 未配置时隐藏 Local time；有值时展示 IANA、固定 offset 和 Local time。
- 新增按 Region 分组的 Time Zone 选择页和搜索空状态。
- Time Zone 在线提交先确认，再返回 Sites 展示不可关闭的保存状态；成功或失败后通过 DONE 关闭。
- Time Zone 离线提交在 Got it 后保存本地并返回 Sites。
- `Not synced to server` 与底部 DONE 共用同一提交入口。
- 普通 name/icon 更新继续使用成功或失败 Toast。
- 所有新增用户可见文案均已补充 English 和简体中文。

## 自动验证

以下 7 项最终回归均通过：

- SiteTimeZoneValueTests
- SiteTimeZoneCatalogTests
- SitePropsEditPolicyTests
- SiteTimeZonePersistenceContractTests
- SitePropsAPIContractTests
- SiteTimeZoneUIContractTests：完整 UI 路由
- SiteTimeZoneUIContractTests：本地化、资源和四 target 归属

以下四个 scheme 均使用 generic iPhoneOS、Debug、关闭签名方式构建通过，退出码均为 0：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

其他静态检查结果：

- `git diff --check` 通过。
- English 和简体中文 Localizable.strings 均通过 `plutil -lint`。
- `all_utc_timezones.json` 通过 JSON 解析检查。
- `CloudSynchronizationManager.swift` 和 `InfoEditViewController.swift` 无差异。
- 生产代码中不存在 `needsFullSiteSync` 或第二版本字段 `sitePropsCloudVersion`。

构建仍会输出工程原有的资源重名、旧 UIKit API、重复 build file 等警告；本次新增的 `keyWindow` 弃用警告已移除。

## 尚需集成验收

当前验证能证明静态契约和四 target 编译成立，但以下内容仍需连接真实环境验收：

- `/sitespace/retrieve/siteprops` 与 `/sitespace/update/siteprops` 的真实服务器请求、回复及错误码。
- App 升级后真实旧数据库迁移、强退重启后的 pending 恢复与重试。
- 在线、离线、超时、服务器字段缺失及非法 timezone 的真机流程。
- 四品牌真机上的 Edit Site、搜索、弹窗、状态卡、Toast 和安全区布局。
- 原整包同步成功后服务器 timezone 的实际落库及下次 retrieve 合并结果。

本次未创建 Git commit。
