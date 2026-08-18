# Gateway 快照持久化与不完整响应合并修复总结

## 修复结果

已修复评审指出的两个 P1 问题：

1. Site 刷新后 Gateway 从数据库重载，注册保护快照不再丢失。
2. clean Gateway 不再使用缺失字段生成的默认值覆盖本地完整配置。

## 1. 最小化注册保护快照

新增 `GatewayRegistrationProtectionSnapshot`，只保存 Gateway Register 为保留 Editor 不可见关联所需的三个 Node 分区：

- `netKeys`
- `appKeys`
- `elements`

快照明确排除：

- `deviceKey`
- `gatewayPreconfigured`
- MQTT 用户名、密码等配置和授权信息
- 其他与 Key/Bind 保护无关的 Node 字段

`GatewayModel` 新增 `registrationProtectionSnapshot`，`gateways` 表新增 nullable Data 字段，并补齐：

- 新数据库建表字段；
- 旧数据库 `addColumn` 迁移；
- `GatewayModel.save()` 序列化；
- `GatewayModel.load()` 反序列化与重新校验；
- `copy()` 生命周期传递。

Cloud Synchronization、Gateway Server Authorization 和 Gateway 页面直接 Register 三个入口均改为读取持久化快照。

## 2. 快照权威性与生命周期

快照更新规则如下：

- Owner 完整响应：明确返回的分区可以替换；未返回的分区仍保留。
- Editor/Visitor 裁剪响应：按 Key index、Element index、Model ID 合并，Model Bind 取并集，不用裁剪数组覆盖完整快照。
- Reset/Re-add 身份变化：新生命周期不继承旧快照。
- 本地 dirty/上传中/删除中且同时检测到远端新生命周期：保留当前本地生命周期快照，避免旧 Node 使用新 Gateway 的 Key/Bind。
- 删除 Gateway 或 Site 时，快照随 Gateway 数据库行一并删除。

## 3. 字段存在性感知合并

新增 `GatewayCloudConfigurationPatch`，从原始 Gateway JSON 解析以下字段：

- Node name
- `gatewayPreconfigured.activate`
- `gatewayPreconfigured.associatedSpaces`
- `gatewayPreconfigured.apn`
- `gatewayPreconfigured.mqttConnectInfo`

每个字段保留三态：

- absent：字段缺失或类型不合法，保留本地值；
- value：字段明确存在且结构合法，更新本地值；
- clear：明确 null；仅在 Owner 完整响应中对 APN/MQTT 等可选配置执行清空，非 Owner 响应中的 null 按权限裁剪处理并保留本地值。

具体保护：

- `gatewayPreconfigured` 整体缺失时，不修改 activate、关联 Space、APN、MQTT。
- 缺少 `associatedSpaces` 不再变成空关联；Owner 完整响应中的明确空数组仍可清空关联。
- Editor/Visitor 返回的关联 Space 按 ID 增量合并，保留响应不可见的本地 Space；裁剪后的空数组不会清空这些关联。
- 任意非法关联元素会使整个关联字段失效，不再通过 `compactMap` 静默形成更短数组。
- 数字 `1` 不再被误当作 Bool。
- 非法 APN/MQTT 类型不覆盖本地配置。
- Node `gatewayInfo` 只更新原始响应明确提供的 project、subnet 或 MQTT 子字段，不再整体复制裁剪对象；非 Owner 的 subnet 响应采用并集合并，MQTT 的 null 不执行清空。

`.mergeFields` 已移除 `cacheGateway.update(gatewayModel: remoteGateway)` 的无条件全字段覆盖。

## 4. 回归测试

新增或扩展覆盖：

- 快照仅包含允许持久化的三个分区；
- Data 序列化/反序列化后 AppKey 和 Model Bind 保持；
- 非 Owner 部分响应保留缺失分区、隐藏 Key index 和隐藏 Bind；
- Owner 完整响应可替换明确返回的分区；
- Reset/Re-add 清除旧生命周期快照；
- dirty 身份冲突不切换快照；
- 缺失配置字段保持 absent；
- 明确空数组与字段缺失语义不同；
- Editor/Visitor 的裁剪关联列表、空数组及 null 不清除本地完整配置；
- 非法关联、Bool、APN、MQTT 不覆盖本地值；
- 无用户名/密码的合法 MQTT 配置仍可解析；
- 源码合同验证数据库列、load/save 和三个 Register 入口。

## 5. 验证结果

已通过：

- `scripts/check_gateway_multi_role_consistency.sh`
- `scripts/check_site_sync_gateways.sh`
- `scripts/check_gateway_associated_spaces_deferred_save.sh`
- `scripts/check_gateway_associated_space_candidates.sh`
- `git diff --check`
- SunSmart Debug / iphoneos / generic device / no signing
- Archipelago Debug / iphoneos / generic device / no signing
- SLG Sync Plus Debug / iphoneos / generic device / no signing
- SylSmart Debug / iphoneos / generic device / no signing

构建只出现工程已有的资源重名、弃用 API、Swift 并发检查等 warning，没有新增编译错误。

## 6. 仍需真实环境验收

自动化测试和 generic iPhoneOS 构建不能证明真实服务端与 Gateway 最终状态，仍需验证：

1. Editor 刷新 Site，退出并重新进入或重启 App 后修改 Gateway 名称，Register payload 仍保留无权限 Space 的 Key/Bind。
2. Editor 收到裁剪的 `gatewayPreconfigured` 时，本地 activate、关联 Space、APN、MQTT 不被清空。
3. Owner 明确解绑全部 Space 时，空数组能够正常收敛并上传。
4. Owner Reset/Re-add 同 MAC Gateway 后，不会携带旧生命周期 Key/Bind。
5. Owner/Editor 写后重新读取 `siteprops`，并检查 Gateway/MQTT/Mesh 设备侧最终配置。
