# 邻近照明统一合并拓扑实施记录

## 结论

已按“统一合并拓扑”完成 App 侧修复。设备最终邻居表不再由 Group 页面或 Space Trigger Zone 页面各自独立覆盖，而是统一由以下三类逻辑关系求并集：

- Group Path 中相邻的前后设备；
- Group Trigger Zone 中同一区域内的其他设备；
- Space Trigger Zone 中同一区域内、可跨 Group 的其他设备。

设备只要仍属于当前 Space 内的邻近照明 Group，就保持邻近照明功能启用；“当前没有邻居”只表示邻居表为空，不再等价于禁用邻近照明。

因此，新增 32 个空的 Space Trigger Zone 后直接保存时，受影响设备集合为空，不会生成任何 Mesh 设备任务，也不会发送 `proximityLightingEnabled(false)`。逻辑数据仍会正常保存并触发云同步。

## 原问题与修复边界

原 Space Trigger Zone 保存流程只按 Space Trigger Zone 计算邻居。空 Zone 会让所有候选设备的 Space 邻居集合为空，旧代码随后直接生成禁用任务，覆盖设备原本由 Group Path 和 Group Trigger Zone 提供的有效关系。

本次没有修改 NordicSigMeshSDK，也没有改变厂商消息格式。修复边界在 App 的拓扑编译、差异比较、保存顺序和同步任务输入。

## 已实施内容

### 1. 统一拓扑策略

新增纯 Swift 拓扑策略，将 Group Path、Group Trigger Zone、Space Trigger Zone 合并为每个设备唯一的目标状态：

- 启用状态；
- 转发次数；
- 去重并排序后的邻居地址表。

同一条邻居关系来自多个来源时只保留一次。删除 Space Trigger Zone 关系后，会自然回退到仍然存在的 Group Path/Group Trigger Zone 关系。

### 2. 统一设备差异决策

所有邻近照明同步入口复用同一个目标状态比较逻辑：

- 目标和设备缓存一致时不生成任务；
- 仅转发次数不同时只更新转发次数；
- 邻居不同时写入完整合并后的邻居表并保持启用；
- 合格设备被历史版本误禁用、且邻居及转发次数已一致时，生成重新启用任务；
- 仅当设备不再属于任何合格的邻近照明 Group 时，才允许生成禁用任务。

### 3. Group 保存链路

Group Path/Trigger Zone 保存时，先用尚未持久化的编辑结果构建统一拓扑并生成任务，再持久化 Group 数据。同步页面只消费已经计算好的任务，不再在页面内部脱离 Space 上下文重新计算。

Group 页面上的“Devices not synced”状态也改为按统一拓扑判断，可用于恢复已被旧版本误禁用的设备。

### 4. Space Trigger Zone 保存链路

Space 保存时先对新 Zone 数据做清理，然后用新数据构建统一拓扑。设备任务范围限定为：

- 旧 Space Zone 与新 Space Zone 成员的并集；
- 且这些设备仍属于当前统一拓扑中的合格邻近照明 Group。

这样既能恢复删除 Space 关系后的 Group 邻居关系，又不会因为空 Zone、无效旧数据或跨 Space 地址去操作无关设备。

### 5. 多 Group 转发次数冲突

一个设备如果同时属于多个邻近照明 Group，而这些 Group 的转发次数不同，就不存在无歧义的单设备目标值。现在不会静默选择某个 Group：

- 添加 Space Trigger Zone 成员时阻止冲突设备；
- Group/Space 保存前阻止相关配置落盘和 Mesh 下发；
- 使用中英文国际化提示用户先统一 Group 设置。

## 已误禁用设备的恢复方式

旧版本已经收到成功 ACK 的禁用命令不会被云同步的 HTTP 200 自动恢复。安装修复版本后，按以下方式处理：

1. 进入受影响设备所在的 Group；
2. 打开 Path/Trigger Zone 页面；
3. 页面会按统一拓扑显示 “Devices not synced”；
4. 点击该提示执行重新同步，或者不修改数据直接保存；
5. 如果设备邻居表仍正确，只会下发重新启用；如果邻居表也有偏差，会下发完整的合并邻居表并启用。

如果多个 Group 均有受影响设备，需要逐个 Group 完成同步。设备 ACK 成功后，还应实际触发邻近照明验证行为是否恢复。

## 自动化验证

- Path topology persistence contracts：通过；
- Proximity Lighting topology policy tests：通过；
- GroupPathSequenceDeviceAddView layout contracts：通过；
- `git diff --check`：通过；
- Xcode 工程文件 `plutil` 检查：通过；
- SunSmart Debug iphoneos 通用真机构建：通过；
- Archipelago Debug iphoneos 通用真机构建：通过；
- Lumineux Debug iphoneos 通用真机构建：通过；
- SylSmart Debug iphoneos 通用真机构建：通过；
- SLG Sync Plus Debug iphoneos 通用真机构建：通过。

构建中仍有工程既有的资源符号重复、旧 API、MainActor 和重复 Build File 等警告，本次未扩大范围处理。

## 真实设备验收清单

1. 保持 Group Path 和 Group Trigger Zone 已配置，在 Space 页面新增 32 个空 Trigger Zone 并保存：应直接返回，不进入设备同步页，日志中不得出现禁用邻近照明消息。
2. 在 Space Trigger Zone 中加入同 Group 设备：最终邻居表应为 Group 与 Space 关系并集。
3. 在 Space Trigger Zone 中加入两个转发次数相同的不同 Group 设备：双方应保留各自 Group 邻居并新增跨 Group 邻居。
4. 删除 Space Trigger Zone 成员：仅同步旧/新成员，设备应回退到 Group 拓扑，不得被禁用。
5. 使用已经被旧版本禁用的设备执行 Group 重新同步：应看到启用或完整邻居设置任务，ACK 后邻近照明行为恢复。
6. 构造同一设备所属 Group 转发次数不同的情况：应显示国际化冲突提示，不保存逻辑配置、不发送 Mesh 消息。
7. 分别确认 Mesh ACK、App 本地缓存、重新进入页面后的同步状态，以及真实邻近触发行为；云同步 HTTP 200 只表示逻辑数据上传成功。

## 尚未覆盖

- 尚未连接真实 Mesh 设备复测本次日志场景；
- 尚未验证固件在大邻居表及跨 Group 合并关系下的容量边界；
- 尚未做服务器下载到另一台手机后的端到端恢复测试。
