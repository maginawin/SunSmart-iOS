# Editor 孤立 Group 快照同步失败分析与修复

## 现象

Editor 在 Site 页面看到 `Some data in the space has not been synchronized to the server`，点击 Confirm 后同步失败，日志为：

`[SpaceSnapshotExport] rejected orphanedGroupMembership nodes=["008C", "008F", "0099", "009C"]`

## 原因

弹窗来自 `SpaceData.needUploadCloud`：本地 `lastUpdate` 大于 `lastUploadCloudTimestamp` 时，Space 被判定为需要上传。

Confirm 会触发完整 Space 导出。前一轮修复增加了孤立 Group 成员保护，只要节点仍为 `inGroup`、但本地找不到对应 Group，就直接拒绝导出。当前四个节点满足该条件，因此同步失败；失败状态被持久化后，弹窗会继续出现。

保护本身避免了本地误删 Group 后覆盖服务器，但没有区分以下两种情况：

1. 服务器仍有完整 Group，本地意外丢失：必须阻止上传。
2. 服务器当前快照本来就具有完全相同的孤立关系：允许 Editor 上传其他待同步修改不会进一步删除服务器 Group，但必须保留异常关系且不得触发邻近照明归一化。

## 修复策略

完整 Space 导出前增加服务器基线验证：

- 本地没有孤立 Group 成员时，沿用原上传流程，不增加请求。
- 本地存在孤立成员时，先调用 `/sitespace/get/spaceprops` 获取服务器当前快照。
- 服务器仍包含本地缺失的任意 Group 时，拒绝上传，避免删除服务器数据。
- 本地孤立成员不是服务器已有孤立成员的子集时，拒绝上传，避免传播新的本地损坏。
- 本地 Group 没有丢失服务器现有 Group，且孤立成员与服务器基线匹配时，允许上传其他修改。
- 基线验证期间本地 Group/孤立成员集合发生变化时，拒绝本次上传，避免使用过期验证结论。
- 经服务器确认的孤立状态在导出时原样保留，不运行邻近照明生命周期 commit，避免把残留邻居关系自动清空或产生 Mesh 同步任务。
- 手动导出本地备份不依赖服务器验证；即使服务器不可用，也允许把当前异常快照完整导出，同时同样不执行邻近照明自动清理。

这项兼容逻辑不负责重建已经丢失的 Group 1，也不会把残留订阅推断为完整 Group。Group 1 仍需由具有完整本地快照的 Owner 或服务器历史数据恢复。

## 当前案例的预期日志

如果服务器仍是本次提供的快照，Editor 再次 Confirm 时应依次看到：

- `/sitespace/get/spaceprops` 成功；
- `[SpaceSnapshotExport] verified remote orphanedGroupMembership nodes=["008C", "008F", "0099", "009C"]`；
- `[ProximityLightingExport] preserved orphan state reason=verifiedRemote`；
- `/sitespace/sync/spaceprops` 请求与成功响应。

如果服务器已经由 Owner 恢复 Group 1，Editor 的旧残缺本地数据将被拒绝上传，日志会显示 `reason=remoteSnapshotDiffers`，从而避免再次删除 Group 1。

## 自动验证

- Path/Proximity Lighting 六组契约测试通过。
- 新增导出策略用例覆盖：正常快照无需服务器验证、相同远端孤立关系可上传、新增本地孤立关系不可上传、服务器 Group 不得被本地残缺快照删除。
- `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 的 generic iPhoneOS Debug 构建通过。
- 真机上的 GET、导出、POST 以及后续 Owner 进入结果仍需联调确认。
