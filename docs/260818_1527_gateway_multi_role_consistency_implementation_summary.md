# Gateway 多角色一致性修复实施总结

## 目标

在不修改后端接口、不为 Gateway 新增云端 `updateTimestamp` 的前提下，修复 Owner 与 Editor 看到不同 Gateway 名称、Editor 部分 Space 权限下关联数据可能被覆盖，以及 Gateway 页面误报 `Devices not synced` 的问题。

## 已实施方案

### 1. Gateway 云端数据合并

- `get/siteprops` 返回 Gateway 时，不再只依赖缺失的 Gateway `updateTimestamp` 判断是否导入。
- 本地 Gateway 为 clean 状态时，幂等合并服务器返回的名称、关联 Space、MQTT 与 Gateway 信息。
- 本地存在待上传、正在上传或删除中的 Gateway 时，保留本地数据，避免服务器旧快照覆盖用户刚完成的修改。
- 检测 Gateway UUID、unicast address、device key 变化；Owner 重置并重新添加后，即使 MAC 相同也按新的 Gateway 实例替换本地缓存。
- 只有 Owner 的完整 Gateway 快照才允许删除服务器响应中缺失的本地 Gateway；Editor/Visitor 的不完整响应不再触发误删除。

### 2. 不增加后端 Gateway `updateTimestamp`

- Gateway 修改仍使用现有 `gateway/register` 上传链路与本地 `GatewayModel.lastUpdate` / `lastUploadCloudTimestamp` 状态。
- 所有本地 Gateway 修改 generation 改为严格单调递增，避免同一秒连续改名、绑定或解绑 Space 时第二次修改未被识别。
- `site.updateTimestamp` 继续只作为 Site 快照版本，不用于判断单个 Gateway 是否更新，避免扩大现有同步语义。

### 3. Editor 部分 Space 权限保护

- 统一 Space 可编辑条件：必须同时满足 `canEditing` 与 `.edit` device operation。
- 保存关联 Space 前重新请求服务器当前关联关系，并比较打开页面时的基线：
  - 服务器拓扑未变化时，只执行当前角色有权限的新增/解绑。
  - 服务器拓扑已被其他设备修改时，取消本次保存并加载最新关联数据。
  - Editor 尝试修改无权限 Space 时拒绝保存并恢复服务器数据。
- 绑定/解绑请求部分成功、后续失败时，重新读取服务器结果，避免 UI 与服务器继续分叉。
- Editor 注册 Gateway 时，将服务器快照中的不可见 key/bind 信息与本地 payload 合并，防止部分权限 payload 删除未共享 Space 的配置。
- 删除入口保持现有 UI；真正执行删除或强制清除前继续做运行时权限校验。

### 4. `Devices not synced`

- Gateway 期望的 subnet AppKey index 改为来自 `gateway.associatedSpaces`。
- 不再使用 Editor 本地 Mesh 中可见的全部 secondary AppKey 推导网关关联状态。
- Owner 与 Editor 使用同一关联 Space 口径比较 Gateway `subnetAppkeyIndexs`，避免部分权限客户端误报未同步。

### 5. 用户提示与本地化

新增并同步 English、简体中文提示：关联 Space 已在其他设备变化时，告知用户已加载最新数据。

## 验证结果

已通过：

- `scripts/check_gateway_multi_role_consistency.sh`
- `scripts/check_site_sync_gateways.sh`
- `scripts/check_gateway_associated_spaces_deferred_save.sh`
- `scripts/check_gateway_associated_space_candidates.sh`
- `git diff --check`
- `SunSmart` Debug / iphoneos / generic device / no signing 构建
- `Archipelago` Debug / iphoneos / generic device / no signing 构建
- `SLG Sync Plus` Debug / iphoneos / generic device / no signing 构建
- `SylSmart` Debug / iphoneos / generic device / no signing 构建

构建仅保留工程原有的资源重名、弃用 API、Swift 6 capture 等 warning，没有新增编译错误。

## 尚需真实环境验收

- Owner 将 `Gateway111` 修改为 `Gateway1` 后，Editor 重新进入 Site 能显示 `Gateway1`。
- Owner 重置并重新添加同 MAC Gateway 后，Editor 能识别新的 UUID/address/device key 并替换旧缓存。
- Editor 只拥有部分 Space 时，改名或编辑可见关联不会删除无权限 Space 的 key/bind 数据。
- Owner 与 Editor 的 Gateway 页面均不再误报 `Devices not synced`。
- Editor 无权修改的 Space 在并发新增、解绑情况下不会被本地旧页面覆盖。

以上真实设备、服务器写后读回、MQTT 与 Mesh 配置同步结果不能由本地测试和无签名构建替代。
