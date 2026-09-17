# Space 3 同步失败日志分析

## 结论

本次失败发生在云端上传结果的回读一致性校验：本地持久提交的期望配置含 3 个设备，`get/spaceprops` 返回的 `nodes` 只有 2 个，缺失地址 `0023`、UUID SHA-256 前缀 `e9cc8a9876f5e7ae` 的设备。三次回读均不匹配后，App 设置 `uploadReadbackConflict`，保留未确认提交及同步失败状态。

该日志能确定读回的设备集合与提交记录不一致，不能确定设备究竟在原始请求、服务端写入、查询组装、缓存或后续并发修改的哪一层缺失。未取得原始上传完整请求及服务端证据，不应直接断言数据库漏写。

## 日志证据

- Space：`49CF0334-24E6-42E5-A8C9-0A5F30368A4F`（Space 3）。
- 提交 ID：`6790E269-44FD-417D-87DF-7C68D138A2AD`，阶段 `accepted`，尚未 `verified`。
- `submittedNodes=3`、`remoteNodes=2`、`remoteDeviceCount=3`：远端设备统计仍为 3，但实际返回数组只有 2 项。
- `missingRemoteNodes=1`、`extraRemoteNodes=0`：少了一台设备，没有额外设备。
- 提交、当前本地及回读时间戳均为 `1789122239`，但 `canonicalEqual=false`：相同时间戳不能证明配置一致。
- 两轮各三次回读均报告相同配置哈希和差异；期间仅见 `get/spaceprops`，未见新的上传请求。
- 请求均为 HTTP 200、业务码 200，解压与解码完成。日志末尾的明确失败原因为 `uploadReadbackConflict`。

## 源码核对

### 设备数量及差异的含义

`SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift`：

- `configurationData` 将每个原始 `nodes` 项映射为成员信息，提取 UUID、单播地址、组地址和组状态，并按单播地址排序；没有按在线状态或配置完成状态过滤设备。
- `readbackDiagnostic` 的 `remoteNodes` 直接取响应 `nodes` 数组长度，`remoteDeviceCount` 单独读取统计字段。
- 因此本例不是将离线设备排除导致的数量差异，也不是日志文本截断造成的数组计数减少。
- `memberships[1]` 从 `0023` 对应到 `0026` 是缺项后排序数组发生位移；结合 UUID 集合只有一个缺项，不能解释成设备地址被改写，或有两台设备丢失。

### 为什么点击重试仍失败

`SunSmart/Common/Cloud/CloudSynchronizationManager.swift:978` 在发起新的上传前调用 `resumeUpload`，失败就结束本轮操作。

`SunSmart/Common/Data/SpaceConfigurationSafety.swift:467` 的 `resumeUpload`：

1. 读取持久保存的 submission。
2. 请求 `spaceInfo` 并将远端逻辑配置与提交记录比较。
3. 最多尝试三次，前两次不匹配后各等待 0.5 秒。
4. 三次仍不匹配，设置 `uploadReadbackConflict` 并返回 `configurationUploadUnconfirmed`。
5. 只有验证通过才会进入 `finishSubmission`，清除同步错误及未确认提交。

本例的 `phase=accepted` 表示本地已有接受阶段记录，不等于远端内容完整性已经确认。代码也存在将历史待确认导出迁移成 accepted 记录的兼容路径，因此仅凭该字段不能还原最初上传响应。

两轮均使用同一 submissionId，说明重试是在恢复同一笔未完成校验的提交；远端数据未变化，就会再次失败。

### 为什么重新进入 Site 没有修复

`SunSmart/Common/Data/ImportData.swift:1637` 在 `preservesLocalChanges` 为真时保留本地配置，不用远端覆盖它。

`preserved pending local deletion/recovery` 是复用的保护日志；`SpaceConfigurationSafety.swift:164` 表明存在未完成 submission 就可能触发，不能据此认定用户删除了设备。

Space 1、Space 2 因服务端时间戳不比本地新而跳过导入，是正常分支。`SiteDeviceOwnership needsRepair=false` 也不能证明远端设备列表完整。没有证据把 `XPC connection invalid` 与本次明确的回读冲突关联起来。

## 下一步定位所需证据

1. 找到该提交最初的 Site/Space 上传请求、业务响应及本地提交快照，核对设备 `0023` 是否完整进入实际请求体。
2. 若请求体包含该设备，核对服务端对应 Space 的节点存储、归属关系以及 `get/spaceprops` 的查询组装，解释为什么 `deviceCount=3` 却只返回两个节点。
3. 查询该设备是否被其他 Space 更新、去重、迁移或删除流程影响，并核对并发更新与缓存版本；这些目前都是待验证方向。
4. 若完整原始响应实际有三个节点、App 解析后才剩两个，再检查客户端网络解码链。本次响应正文已截断，无法逐项独立核验完整原文。

不应通过只比较时间戳或 deviceCount、跳过成员校验来把这次同步标记成功，否则会掩盖缺失设备。

本次仅分析用户日志并核对当前源码，新增本分析文档；未修改业务代码、未访问服务端、未执行构建或真机测试。
