# Space 同步回读校验引入时间与旧版行为

## 结论

是的。当前分支的 Git 历史证明，Space 上传后检查云端逻辑配置的功能于 2026-09-07 加入。此前该同步入口在上传接口返回成功后直接标记同步成功，不会立即读取 Space 节点列表核对。因此，服务端即使仍从 Redis 返回旧 nodes，只要上传响应成功，旧流程就不会因此报同步错误。

用户本轮已确认服务端根因：上传 nodes=[] 后 Redis 缓存未清理干净，get space 仍返回旧节点。本结论采用该现场确认，未独立访问服务器。缓存问题从何时开始存在，仍需服务端历史证据，App Git 历史不能证明。

## Git 证据

时间为提交记录的 UTC+08:00；表示代码进入提交的时间，不代表 App 发布或安装时间。

| 提交 | 时间 | 行为 |
| --- | --- | --- |
| `d4e4e436` 的父版本 | 2026-09-07 校验加入前 | CloudSynchronizationManager 收到 request 的 success，直接设置 state=successful；syncSpace 将 lastUploadCloudTimestamp 设为 lastUpdate，清除 syncCloudError 并保存。没有紧随上传的 Space 配置回读比较 |
| `d4e4e436`，fix: space trigger zone sync issues | 2026-09-07 15:01:04 | 新增 SpaceConfigurationSafety / IntegrityPolicy；共享上传入口在已有 Space 上传成功后请求 spaceInfo，比较提交和远端的 configurationData，其中已包含 nodes 提取的 memberships；不匹配则阻止成功确认。该初版对 siteAdd 仍有例外 |
| `abfbe5a7`，fix: space trigger zone bugs | 2026-09-07 17:46:06 | 扩展持久化提交和恢复流程，包括 markSubmissionAccepted、resumeUpload、三次回读、uploadReadbackConflict，以及 configurationUploadUnconfirmed / -2002 |

比较文件：`SunSmart/Common/Cloud/CloudSynchronizationManager.swift`、`SunSmart/Common/Data/SpaceConfigurationSafety.swift`、`SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift`、`SunSmart/Common/Network/NetworkRequest.swift`。

## 对本次现场的解释

- 旧流程：上传空列表 → 服务端响应成功 → App 标记已同步。Redis 中的旧节点不会在这一步被发现。
- 当前流程：上传空列表 → 服务端响应成功 → 回读仍有两台节点 → 成员不一致 → 保留本地待确认数据并报告同步冲突。
- 因此，新增校验暴露了服务器写入与读取结果不一致的问题。当前设备成员 0 对 2 的冲突应继续保留校验，不能通过忽略差异恢复旧版的成功提示。
- 旧缓存后续是否会把已删设备重新带回 App，取决于重新进入、版本判断及导入路径；本次没有复现旧版，不能认定过去一定发生过设备恢复。
- 服务端修复并清理目标缓存后，若回读设备成员与本地空配置一致且没有其他配置差异，现有 pending 提交可通过回读确认；实际结果应通过一次重新同步及重启后的读取验收。

本轮仅核对 Git 历史并新增本文，未修改业务代码或运行生产请求。
