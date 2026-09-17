# Site Trigger Zone：SAVE 失败日志分析

日期：2026-09-14。

## 结论

本次 `SAVE` 的 `/sitespace/update/siteprops` 已收到 HTTP 200、业务 `code=200`/`success`，响应还回显了提交的完整 `extensionData`。因此不能把现象归因为该 POST 被服务器拒绝。客户端在 POST 后又调用 `/sitespace/get/siteprops`，只有回读的完整 `extensionData` 与本次目标一致才确认云保存；日志省略了这次 GET 的正文，也没有输出最终 `Failure` 分支，**现有日志不足以判定具体是哪一个回读条件失败**。

最需要排查的是 `siteInfo` 回读没有提供本次目标 `extensionData`，或提供了不同版本。POST 前后两次 `siteInfo` 的解压正文恰好都是 57,020 字节；如果这是首次把 8 个成员写入此前为空的 Zone，长度没有增加值得怀疑，但单凭字节数不能证明正文相同：可能已有等长数据，也可能其他字段同时变化。

## 代码对应

- `SiteTriggerZoneCoordinator.performSynchronization` 的请求成功分支不直接返回成功，而是再次 `retrieve()`，调用 `SiteTriggerZoneStore.receive` 后检查 `current.conflict` 和 `current.serverData == pending.target`。不相等返回 `.unconfirmed`，发生冲突返回 `.conflict`；GET 业务/结构校验失败会归入 `.network` 等错误。
- `SiteTriggerZoneStore.receive` 只从 `siteInfo.data.extensionData` 读取扩展对象；字段缺失时不会确认本地 pending。即使 `sitePropsUpdate.data.extensionData` 已回显成功，这条更新响应也不参与最终确认。
- `nw_connection...unconnected` 出现在 GET 200 前；随后请求完成，不能据此认定网络失败。末尾 Mesh 收发发生在 POST 和回读之后，也没有证据表明它影响了云保存。
- 日志请求成员使用 `triggerElementAddress`，当前仓库代码生成和解析的是 `deviceAddress`。本次运行的 App 与当前源码不是同一版本；它不直接证明本次 POST 失败，但后续升级读取已经写入的旧字段时，需要单独核对兼容性。

## 下一次复现的最小证据

在 `#if DEBUG` 下记录这次 Save 的最终 `Failure` 枚举，并分别为提交前/提交后 `siteInfo` 记录：业务结果、`updateTimestamp`、顶层 `extensionData` 是否存在及类型、`schemaVersion`、目标 Zone 是否存在和成员数、与本次目标是否全量相等。不要打印完整 Site、Mesh Key 或其他敏感载荷。若 `siteInfo` 缺字段或回读旧值，再用只读 `/sitespace/retrieve/siteprops` 请求 `props.extensionData` 对照其 `data.props.extensionData`，区分读取接口契约与写入未持久化问题。不能仅凭 POST 的回显将状态改为“云端已保存”。
