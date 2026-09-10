# 异常 Space 无法删除设备：独立删除记录流程

日期：2026-09-10；工作区：site-trigger-zone。

## 用户选择与交付范围

用户明确选择删除 App 与云端记录，实体设备可以手动恢复出厂。本轮实现异常 Space 的整空间记录删除路径，不再要求用户先恢复密钥、完成配置同步或逐个 Mesh Reset。

修复版操作：从 Site 的 Space 删除入口，或进入 Space 后的 Delete，确认删除 App/云端 Space 与设备记录及手动复位说明。正常未阻断且密钥完整的非空 Space 保留原来的设备数量限制。

本轮只修改源码、测试和本地文档，没有执行生产删除请求，没有操作手机设备。云端接口是否允许非空 Space 删除尚未现场验收；如果服务端拒绝，将保留本地记录并显示实际错误，不能仅用 App 绕过服务端规则。

## 卡住的原因

Lights 批量删除在 `DevicePermanentDeletionContext.prepare()` 准备每个设备的删除日志；必须满足当前 MeshNetwork 对象、Site UUID、Space Network ID、导入状态与检查点条件。任一设备准备失败，在发出 Reset 前就显示 `configuration_deletion_cleanup_pending`，不能到达后续 Reset 失败后的强制删除确认。

所以该文案既可能表示实际清理未完成，也可能表示删除根本尚未开始。本案已确认目标 Network ID 的密钥未注册，当前网络身份检查足以造成此阻断；没有本次逐项 guard 日志，不能据此排除检查点失败或待处理导入等其他原因。重新进入不会凭空补出冲突密钥。

此外，Site 页面和 Space 页面删除入口都以 `deviceCount > 0` 拦截，而空间删除接口本身只使用 `siteId`、`spaces: [spaceId]`、`userId`，并不要求完整配置的 netKey/appKey：`POST /sitespace/spaces/delete`。把整空间删除依赖于 Lights 清空和成功同步，会形成无出口的流程。

本地 `SpaceData.delete()` 原先仅在找到对应 NetKey 时调用 SDK removeSubnetwork；缺 Key 时会遗漏 Mesh nodes/groups/scenes，却继续删除 App Space 行。SDK 的 removeSubnetwork 同样在找不到 Key 时直接返回，不能作为缺 Key 现场的记录清理保证。

## 修复行为

- 两个页面复用 `SpaceConfigurationSafety.requestSpaceRemoval`。记录删除独立于配置导出、完整 Key、拓扑归一化、上传回执和设备 Reset。
- 确认后先保存 SQLite 检查点与可恢复的删除意图，更新 generation，使旧异步回调失效，并取消配置同步。等待云端响应时暂停该 Space 的导入和自动上传、上传回读恢复。
- 云端成功后才进入本地 `removing` 阶段；重试返回资源不存在也可继续本地清理。网络/权限等失败保留数据与待处理意图，用户可再次 Delete；不会在失败后悄悄恢复旧配置上传。
- 异常记录删除显式要求请求云端；不能把本地缺少上传时间当作云端不存在。首次上传尚未确认的提交记录和 Site 创建记录也要求先请求云端删除。
- 已确认云端删除但本地清理中断的，沿用原有本地 removal 重放；页面也可再次重试。只有本地删除返回成功，才从列表移除或退出详情页。
- 缺 NetKey 时仍通过明确的 Site UUID + Network ID 删除节点属性、节点、Mesh Group/Scene 及已有 App 扩展数据。逐项检查删除返回值；不会按 index=1 删除别的子网，不把“密钥缺失”当作整库删除条件。
- 同 Site 其他 Space 使用相同 Network ID 时拒绝本地删除，避免相同存储范围的记录被一起清除。异常非空删除也不开放给主网络或非 owner。
- 复用现有 SRAlertView，无新增页面或布局约束；新增中英文确认与本地清理失败提示。确认时保留当时是否明确选择记录删除的语义，避免弹窗显示后状态变化导致静默升级为强制删除。

注意：删除意图不是云端已删除的证明，`removing` 才是允许本地移除的阶段。HTTP 失败时不调用本地删除。实体设备并未因删除记录而恢复出厂，也不自动回收并重新分配设备实际仍在使用的 Mesh 索引。

## 验证与限制

- `scripts/check_space_recovery_receipts.py`：通过。执行生产删除请求状态逻辑，覆盖旧上传回执保留、删除不上传配置、断网失败、响应丢失后重试、权限与账号变化、已确认后的本地重试、本地空间无需网络。
- `scripts/check_space_record_removal.py`：通过。抽取生产本地删除方法，在隔离持久化替身中覆盖缺 Key 数据清理、另一 Space 和另一 Site 记录保留、原 Key 不变、清理失败可重试、数据库不可用与共享 Network ID 拒绝。
- `scripts/check_proximity_scoped_import.py`、`scripts/check_space_mesh_keys.py`：通过。
- 两种语言 Localizable.strings 的 plutil 检查与 `git diff --check`：通过。
- 最终代码的 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 五品牌 generic iPhoneOS Debug 构建全部通过（直接 xcodebuild，关闭签名，无日志重定向）。未修改 SDK、依赖或工程配置。

回归使用隔离的请求/SDK/数据库替身；实际 SDK API 兼容性由 App 编译验证。弹窗沿用多行标签和纵向自适应约束，完成约束源码检查；没有运行真机布局或真实交互测试，不将静态检查和编译描述为视觉验收。遵从用户默认不自动真机测试和不使用 Simulator 的约定。

尚待实际接口验收：owner 对非空异常 Space 调用独立删除接口能否成功，以及重新拉取 Site 后确认远端已无该 Space。若服务端要求先清空设备，需要服务端提供级联/强制删除能力；本轮未添加未经证实的 force 参数，未伪造密钥来绕过同步校验。

此前 `docs/260910_1438_commit_49cd024_review.md` 的活动网络 staleSnapshot 重试问题不属于这次用户选择的记录删除目标，未顺手修改。
