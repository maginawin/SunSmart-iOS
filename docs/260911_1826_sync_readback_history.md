# Site / Space 上传回读校验的引入时间

根据当前工作树的 Git 历史与源码核对，时间均为 UTC+8。

## 首次引入

- 提交：`d4e4e4364a0c16f33d81f25b7cfd90d0274c2601`。
- 作者时间与提交时间：2026-09-07 15:01:04。
- 标题：`fix: space trigger zone sync issues`。
- 该提交在 `CloudSynchronizationManager.swift` 新增上传成功后的 `.spaceInfo` 请求，将提交的 Space 配置与远端规范化配置比较。覆盖 Space 上传及 Site 上传内嵌的 Spaces；最初跳过首次 Site 创建。
- 引入前，该路径收到上传成功响应后直接更新 `lastUploadCloudTimestamp`；引入后必须回读匹配才确认实际提交的版本。
- 同期文档 `260907_1400_app_only_proximity_compatibility_implementation.md` 第 47 行记录：核对 Profile、Group Path/Zone、Space Zone 和成员归属，无法确认时保留 dirty 并进入保护。

## 后续扩展

- `abfbe5a710107897eea56b8267422e860a0cf162`（`fix: space trigger zone bugs`）加入持久提交恢复的 `resumeUpload`，以及首次 Site 创建中断恢复时的 `.siteInfo` 请求。
- 该提交作者时间为 2026-09-07 17:46:06，实际提交时间为 2026-09-08 11:02:44；不能把两者当成同一个时间。
- 当前 `resumeUpload` 对有效但配置不同的响应最多回读三次，间隔 0.5 秒；持续冲突保留保护状态。网络失败单独返回。

## 当前路径与范围

- `CloudSynchronizationManager.swift:1077`：上传成功后逐 Space 调用 `resumeUpload`。
- `SpaceConfigurationSafety.swift:482`：通过 `/sitespace/get/spaceprops` 回读。
- `CloudSynchronizationManager.swift:965`：仅在本地 Site 尚未标记创建完成、恢复记录中已有创建时间时，请求 `/sitespace/get/siteprops` 恢复创建事实与 provisioner 资源；位于本轮上传之前。
- 因此普通流程不是每次 `sync/siteprops` 后固定请求 `get/siteprops`：Site 上传携带的各 Space 通过 `get/spaceprops` 校验；不带 Space 的上传不执行该逐 Space 校验。

本次仅查阅源码、提交历史和已有文档，未修改业务代码，未执行构建或真机测试。
