# 删除全部 Lights 后云端同步失败分析

## 结论

本次同步失败的直接原因已经由日志确定：App 提交的 Space 配置为 `nodes=[]`、`deviceCount=0`，服务器返回 HTTP 200 / 业务 200；随后 `/sitespace/get/spaceprops` 仍返回原来的 2 个节点。App 连续三次回读发现设备成员不一致，设置 `uploadReadbackConflict`，最终返回本地错误 `-2002`，保留手机数据并要求人工选择恢复方式。

问题应优先沿服务端空列表删除语义及详情读取链路排查。现有证据不能进一步断定是空数组被忽略、设备关系表没有清理、缓存未失效，还是旧数据被其他写入源重新写回；这些需要服务端实现及日志确认。

分析依据：用户提供的现场日志、当前 `trigger-zone-sep` 工作区源码，HEAD `989a5916`。本轮只新增分析文档，未修改业务代码、调用生产接口、执行构建或真机验证。未保存日志中的 Mesh 密钥。

## 日志证据

目标 Site 为 `2E0812F5-9359-4813-B3D4-5F7D2C5E52DF`，Space 为 `07CC372B-E17C-4911-B6FA-000C6BEA7271`。

| 阶段 | 证据 | 含义 |
| --- | --- | --- |
| 启动恢复旧提交 | submissionId=`CE7A3266-656F-4817-A8CB-AB43DDE71E09`，phase=accepted，submitted=1788847190 | 持久化状态记录此前请求已获成功响应；本段没有最初删除及上传全过程 |
| 旧提交回读 | submittedNodes=0、remoteNodes=2、remoteDeviceCount=0，双方时间戳均为 1788847190 | 云端计数和节点列表不一致，时间戳相同也不能证明配置相同 |
| 差异 | memberships.count：0 对 2，远端多出 memberships[0]、memberships[1] | 是实际设备成员差异，不是空字符串或排序差异 |
| Site 上传 | syncSpaceCount=0、spaces=[]，返回成功 | 本次 Site 请求未携带目标 Space 配置，不能证明 Space 删除已同步 |
| Site 查询 | siteInfo 的目标 Space 为 nodes=[]、deviceCount=0 | Site 查询中观察到空列表；该接口可能是摘要投影，不能仅凭此证明设备表已清空 |
| Space 查询 | 多次 spaceInfo 均返回地址 0014、0017 的旧节点 | 详情接口稳定暴露旧节点，未与本地删除结果一致 |
| 人工恢复后新上传 | `/sync/spaceprops` 明确携带 nodes=[]、deviceCount=0、updateTimestamp=1788847265 | 手机确实提交了删除后空配置，没有把旧节点重新带上 |
| 新上传响应 | HTTP 200、code=200、message=success | 写接口接受成功，但尚未确认读端内容 |
| 新上传回读 | 新 submissionId=`A1D7DE79-9EFD-482B-A349-B19B12EB38F3`；remoteTimestamp=1788847265，仍 remoteNodes=2 | 新版本元数据已反映在读取结果中，节点成员仍旧 |
| 最终失败 | attempt=1、2、3 均 mismatch，blocked reason=uploadReadbackConflict，errorCode=-2002 | App 主动拒绝把不一致配置标记为同步成功 |

远端残留节点为 `B2261F55-AD77-4A2F-8DD9-E0AA528815D0` / `0014` 与 `F9ECCA0E-6A63-403F-8613-35F1959CDFC0` / `0017`，PID 均为 `1502`。

新旧提交时间戳相隔 75 秒，期间多次读取都保留相同节点。现象不限于一次上传后的即时读取；但每轮自动回读仅三次、间隔约 0.5 秒，日志仍不能排除服务端更长的异步延迟。

## 源码对应关系

1. `SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift:771`：批量删除创建删除上下文，调用 Mesh Reset；成功后提交本地清理并调用 `commitLocalChangeForCloudSync`。强制删除也进入本地变更同步流程。
2. `SunSmart/Common/Data/DevicePermanentDeletionCleanup.swift:274`：删除完成提示只检查本地删除清理是否仍待处理，不等待云端上传及回读。因此看到 Done 后仍出现云端同步提示，符合现有完成条件。该日志未包含 Reset 回调，无法单独确认两台实体设备的复位结果。
3. `SunSmart/Common/Cloud/CloudSynchronizationManager.swift:960`：保存待提交快照，发起请求，成功后标记 accepted，再调用 `resumeUpload`；只有校验成功才完成整个同步任务。
4. `SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift:161`：将 nodes 的 uuid、unicastAddress、groupAddress、groupState 提取成 memberships 后比较。deviceCount 和时间戳不是替代设备成员校验的依据。当前已兼容 groupAddress 缺省与精确空字符串，本次 0 对 2 的差异不属于此前空地址兼容问题。
5. `SunSmart/Common/Data/SpaceConfigurationSafety.swift:462`：恢复提交时最多回读三次，失败后在第 524 行 block 并返回 configurationUploadUnconfirmed。错误码 -2002 来自 App，同步上传接口本身返回的是业务 200。
6. `SunSmart/Common/Data/ImportData.swift:1561`：存在待确认提交/删除恢复时保留本地配置，打印 preserved pending local deletion/recovery。因此普通刷新不会将云端旧节点直接导入本地。
7. `SunSmart/Main/Space/Controller/SpaceViewController.swift:1523`：blocked 且需要配置审核时，导航栏失败图标进入配置恢复弹窗。它不要求存在另一台手机并发修改；上传回读冲突本身足以触发。

## 两个恢复选项为何不能直接解决

### Use this phone’s data

`SpaceConfigurationSafety.authorizeLocalRecovery` 检查当前完整本地快照和权限，读取远端基线，保留恢复快照，生成更新版本并允许重新上传。随后页面触发 syncSpace。

日志中的新提交、新时间戳及 nodes=[] 与此路径一致。新上传之后仍回读出两台旧设备，所以再次失败。仅重复点击不能解决详情接口持续返回旧节点的问题。

### Reload cloud data

当前 `reloadConfigurationFromCloud`（SpaceViewController.swift:1615）读取远端后调用普通 `space.update`。该导入仍受 `preservesLocalChanges` 保护，没有专用的显式放弃本地待确认提交入口。

因此在本次 accepted 提交和 blocked 均保留的状态下，源码预计会保留本地数据，随后因 blocked 未解除提示重载失败。这是恢复入口的独立行为缺口，不能解释最初的远端设备残留。所给日志没有明确记录用户实际选择 Reload 后的结果，此判断属于静态源码分析。

## 后续排查与修复方向

优先在后端跟踪本次 Site/Space 和版本 1788847265：

1. 核对 `/sync/spaceprops` 对显式 `nodes=[]` 的合同：是否表示清空该 Space 的设备成员，还是被非空判断或增量合并逻辑当作不更新。区分字段缺省与显式空列表。
2. 检查 Space 元数据、节点表及 Space-Node 关系是否在同一有效删除流程中更新；以本次两个 UUID 检查删除后实际归属。
3. 检查 `/get/spaceprops` 的 nodes 来源：数据库关联查询、缓存、读副本或后续拼装逻辑。确认删除对应的缓存失效及读取版本一致。
4. 对照 `/get/siteprops` 和 `/get/spaceprops` 的接口合同，确认前者 nodes=[] 是否固定摘要行为，避免用摘要空列表误判完整设备列表已清理。
5. 若删除事务实际完成，继续查网关上报或其他客户端是否重新插入节点；当前日志没有证明存在这样的写入。

App 应保留真实成员冲突校验，不以 deviceCount=0、时间戳相同或 HTTP 200 直接确认成功。若修复 Reload 入口，应明确处理用户放弃本地提交的语义、备份及回调失效边界，不能只绕过保护条件。以上为建议，尚未实施。

建议验收：添加两台 → 删除其中一台 → 确认完整 Space 回读只剩一台；删除最后一台 → 回读 nodes=[] 且 deviceCount=0 → 待确认提交完成、同步提示消失；重启和重新进入 Space 后仍无旧节点。还需覆盖本地恢复重试及明确选择云端重载两条路径。

## 其他日志

- AppleLanguages、空 App Group identifier、XPC、EFC proxy filter 提示没有出现在本次配置比较失败条件中，不能据此解释成员差异。
- DNS 查询有超时诊断，但关键请求均已获得业务成功响应；最终错误链是回读内容不一致。
- Content-Encoding 声明 gzip 而 actualBodyGzip=false 是独立请求编码异常。当前源码压缩分支被注释，仍设置 gzip 头。应另行校正；本次新时间戳成功出现在回读中，不支持把最终冲突直接归因于请求完全无法解析。
