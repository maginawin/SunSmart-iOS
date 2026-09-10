# Space 密钥缺失修复与现存项目兼容性

日期：2026-09-10。工作区：site-trigger-zone。

## 结论与实施边界

按用户确认实施上传校验与无冲突补齐。采用“同一 Site 的 NetKey 索引空间、AppKey 索引空间各自唯一，不同 Site 可以复用索引”的边界；NetKey index=1 与 AppKey index=1 并不互相冲突。

本轮没有启动全库迁移，没有修改既有密钥值、重新分配索引或向设备发送密钥配置命令，没有修改 SDK、生产云数据或用户导出的手机容器。符合现有绑定规则的项目沿用原密钥与索引；完全一致的密钥对只校验，不调用密钥保存。

不能把升级描述为对所有历史异常项目“完全无影响”。缺失、碰撞、绑定歧义或无法证明完整性的项目会明确停止相关导入/上传，避免继续提交缺字段 JSON。现场同索引不同密钥的 Space 仍未恢复可用，不能把阻止 500 等同于现场恢复完成。

## 现存项目的行为

| 状态 | 升级后的行为 | 数据变更边界 |
| --- | --- | --- |
| 密钥、索引、绑定完整且一致 | 正常导出并同时携带 netKey、appKey、appKeyIndex | 密钥校验不写库，不重编号 |
| 不同 Site 使用相同索引 | 独立处理，继续支持 | 不引入跨 Site 唯一性约束 |
| 同一 Site 已保存完全一致的密钥对 | 复用原值 | 不重新生成或替换 |
| 只缺 AppKey 或缺整对，目标索引未冲突 | 从有效远端配置补齐，保存后重载核对 | 只添加缺失项，保留其他 Space 密钥 |
| 同索引不同密钥、绑定冲突、多个候选 AppKey | 停止并记录明确错误 | 不覆盖已占用索引，不任选一把兜底 |
| 本地与远端 Key Refresh 状态不一致 | 保留原状态，要求单独处理 | 不把密钥轮换当普通覆盖 |
| 调用者快照与最新数据库密钥清单不同 | 本次修复在写入前停止 | 避免过期快照遗漏其他 Space 的密钥；后续以新快照重试 |
| 旧恢复回执没有密钥摘要 | 仅在同 UUID、时间戳、业务配置的完整快照可证明时补摘要 | 无证据则保留待处理回执，不冒充成功 |

新校验也会拦截旧版本曾容忍的异常结构，例如重复索引、同 Network ID 对应不同索引以及一个 Space 子网存在多个候选 AppKey。不会自动清理这些数据；需要针对具体异常确认处理方式。当前没有改变创建流程的索引分配算法，也没有宣称所有产生历史冲突的来源已修复。

## 代码改动

1. `SpaceConfigurationIntegrityPolicy.swift` 增加共享密钥策略，检查存在性、类型、范围、完整 Key、绑定、节点引用、索引冲突和轮换状态。密钥证明使用私有摘要，诊断不输出密钥值。
2. `ExportData.swift` 增加 SDK 适配层，按 Space 的 Network ID 精确选择密钥，必需字段不再通过可选编码被静默忽略。Site 根级导出同样要求完整密钥。补齐使用新读出的 Site 数据库快照，并在写入前校验调用者清单、写入后重载验证。
3. `ImportData.swift` 移除“仅按 NetKey index 命中就跳过两把 Key”的旧分支。无冲突的密钥补齐放在拓扑保留返回之前；保留待上传业务配置时也可独立补齐有效密钥，不更改业务拓扑或清除回执。
4. `SpaceConfigurationSafety.swift` 对上传准备、提交回执、完整快照和回读增加密钥校验。相同业务拓扑但密钥不同不能确认上传成功。缺字段快照不能覆盖上一份完整导出。
5. 恢复回执新增可选摘要字段，保持旧 JSON 可解码。新增两条中英文错误文案，共享品牌资源沿用现有配置。

SDK `MeshNetwork.save(allData: false)` 默认只保存网络记录；此次补齐没有要求写入 nodes/groups/scenes。修复入口有串行保护，且先读取最新数据；这不是对整个 SDK 所有写入路径的全局事务改造，也不宣称 App 与 SDK 两个数据库具备跨库原子提交。

## syncSite 影响

`syncSpace`、携带 Spaces 的 `syncSite`、`addSpaces`、初次 `siteAdd` 共用 Space 导出校验。Site 聚合已有数量校验：任何选中 Space 导出失败，整次返回失败，不静默丢掉该 Space 后发送部分数据。

仅同步 Site 元数据时不校验未携带 Space 的导出；Site 自身根级密钥仍必须有效。根级有效不能代替检查嵌套 Space。

## 验证

- `scripts/check_space_mesh_keys.py`：通过。执行真实策略和抽取的生产 SDK 适配层、Site 聚合代码；覆盖缺 AppKey、碰撞、跨 Site 复用、同值幂等、保存失败、旧快照、补齐时保留其他 Space，以及拒绝部分 Site 上传。
- `scripts/check_space_recovery_receipts.py`：通过。覆盖缺 Key 不提交/不覆盖备份、错误密钥回读不能确认、旧回执证明与保留、恢复权限和异步上下文回归。
- `scripts/check_proximity_scoped_import.py`：通过。拓扑导入、删除与恢复生命周期回归。
- `SpaceConfigurationIntegrityPolicyTests`：编译、运行通过，覆盖配置比较、空 Group 地址兼容与提交版本。
- 中英文 Localizable.strings 的 `plutil -lint`：通过；`git diff --check`：通过。
- 最终代码的五品牌 generic iPhoneOS Debug 构建：SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 全部 `BUILD SUCCEEDED`，关闭签名；使用直接 xcodebuild，无日志重定向。

适配层测试使用隔离的 SDK 类型/持久化替身；实际 SDK 类型兼容性由 App 构建验证。这些检查不替代真实数据库升级、服务端上传回读和设备控制验收。未使用 Simulator，未进行真机测试，未发送生产同步请求。

## 现场后续

目标 Space `E335D681-CB9B-48C1-8A6F-223706D4E70D` 与同 Site 另一个 Space 的 index=1 密钥冲突。按用户“保护现存项目”的要求，本轮明确不自动迁移它。迁移不能仅改上传 JSON：设备上的 NetKey/AppKey 引用、Model bind 与网关上下文也需一致。具体恢复需先确认历史来源及设备侧实际状态，再单独规划，不在此次升级中隐式执行。

历史根因与提交追溯见 `260910_1413_space_export_missing_mesh_keys_analysis_plan.md`。本文件描述已实施范围，不将原计划第三阶段记为已完成。
