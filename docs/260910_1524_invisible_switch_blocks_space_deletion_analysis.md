# Space 中不可见 Switch 阻止删除：原因与修复规划

日期：2026-09-10。工作区 site-trigger-zone，当前 HEAD 61b7e8b9。本轮仅分析源码、日志及历史容器，不修改业务代码，不删除记录，不调用生产 API。

## 结论

目标 Space 的持久化数据作用域与页面显示/删除所用的 Mesh 作用域不一致。Space 缺失目标 NetKey，云端 Key 又因索引冲突不能导入；SDK 没有因此停止进入 Space，而是允许 currentNetworkKey 回退到首个 Key。Switch 列表使用这个活动 Key 的 Network ID 查扩展表，所以读到其他子网的 Switch 缓存；Space 删除检查却按正确的目标 Network ID 查表。因此真实记录可以阻止 Space 删除，却在页面中不可见。

上一轮修复覆盖了 Mesh Node 的普通/强制删除，并收紧了空 Space 检查；未同步解决 DeviceSwitchData 虚拟记录页面和删除操作对全局 Mesh Key 的依赖，这是覆盖缺口。不能以恢复非空 Space 删除放行来处理。

## 证据

### 本次日志

- 目标 Space：E335D681-CB9B-48C1-8A6F-223706D4E70D。
- 拉取 siteInfo/spaceInfo 均成功；目标 Space 多次在导入中出现 `meshKeys:netKeyIndexConflict` 后结束。
- 导出时出现 `networkReused`，随后 `meshKeys:missingNetKey`；本次该导出在本地结束，没有发出 spaceUpload。
- 即使导入被保护拦截，后续仍出现“加载网络扩展数据完成”和进入 DeviceSwitchesViewController。
- `SiteDeviceOwnership identities=0` 是 Mesh 设备身份预检，不统计独立虚拟 Switch 表，不能证明 Space 已完全清空。
- 本段未打印 Switch 查询 scope、当前 Key Network ID 或删除 Space 的请求；具体当前错误子网值不能只凭日志确定。名字筛选状态也未打印，但缺 Key 下的错误作用域路径已由源码证实。

### 当前源码与 SDK

| 环节 | 位置与行为 |
| --- | --- |
| Site 卡片 | `SpacesViewCell.swift:69` 显示 Space 的 switchesCount 摘要 |
| 正确摘要刷新 | `SpaceViewController.swift:119` 的 refreshSummaryCountsFromSpaceMesh 按 space.meshUUID + space.meshNetworkId 查 DeviceSwitchData |
| 空 Space 检查 | `MeshNetwork+SunSmart.swift:466` 的 canDeleteEmptySpaceRecords 同样直接按目标 Space 查持久化记录 |
| 进入 Space | `SpaceViewController.swift:702` 先 setMeshNetworkConnected，再 loadExtensionData；不证明成功选择了目标 Key |
| SDK Key 选择 | `MeshLibManager.swift:183` 只有找到目标 Network ID 对应 Key 才赋值；`:1084` 的 getter 在未赋值时回退首个 Key |
| 扩展加载 | `MeshNetwork+SunSmart.swift:620` 从 currentNetworkKey.networkId 取查询子网，然后在后台加载 Switch、Schedule、Dongle 等 |
| Switch 页面 | `DeviceSwitchesViewController.swift:245` 基于全局 manager.switchs 生成筛选后的 visibleSwitches |
| Switch 删除 | `DeviceSwitchesViewController.swift:420` 调用 manager.deleteSwitch；`MeshNetwork+SunSmart.swift:963` 用当前 Key 的 Network ID 删除记录和侧表，且从当前网络解析代理/Group |
| 摘要再次覆盖 | `SpaceViewController.swift:1217` 附近还会把 manager.switchs.count 写回 Space 摘要，可能让错误范围的空缓存进一步导致计数变化 |

已核对 SDK 本地 HEAD 与工程 Package.resolved 一致，均为 a6246b1b0409824a3227a9c7cad8140219feb182。

### 历史容器佐证

只读检查用户先前提供的 2026-09-10 14:00.56.775 xcappdata，读取 AppData/Documents 对应账号目录中的 sunsmart.sqlite3。它早于本次日志，不冒充最新手机数据库：

| 记录 | 内容 |
| --- | --- |
| Space | Space 1 trigger；E335D681-CB9B-48C1-8A6F-223706D4E70D |
| Network ID | AF566D68DE2263A0 |
| switchesNumber | 1 |
| switchId | B2E40EAC-B7F8-4403-AC2D-17A0F0C2651D |
| Switch 名称 | Switch 1 |
| switchs 表归属 | 同一 Site，subNetworkKey=AF566D68DE2263A0 |
| panelType / enabled | 0 / 1 |

同 Site 的另外两个 Space 在该历史容器中 Switch 计数均为 0。目标记录存在于 switchs 表；该 Site 没有对应的 pjEightKeySwitchs 行。未输出凭据或密钥。

## 调整修复规划

1. **浏览数据按明确 Space 作用域加载。** Switch 列表、底部计数、Site 摘要、删除检查统一基于目标 Site UUID + Space Network ID。缺 Key 仍允许查看其本地记录；不得借首个 Key 或其他 Space 的 Key 来确定记录范围。
2. **隔离通信与浏览上下文。** 目标 Key 缺失/冲突时禁止该 Space 发 Mesh 写操作；保留本地记录浏览与授权删除。扩展数据异步加载时捕获请求的 Site/Space/generation，切换后丢弃旧结果。不要简单把目标 Switch 填到错误的全局网络缓存中，否则 proxyNode、linkGroup 等依然可能解析到错误设备。
3. **Switch 记录删除也按明确作用域。** 使用目标 Space + switchId 删除基础表、对应侧表和已确认的局部引用；通信不可用时允许明确确认强制删除本地记录。只有成功持久化并回读后移除列表项，保留云端待同步保护。避免 manager.deleteSwitch 在错误 Key 下删除同 ID 的其他 Space 记录、错误解绑代理或清理其他 Group。
4. **统一数量与实际记录。** 不再用身份不匹配的 manager 缓存覆盖 Space 摘要；删除后按目标持久化范围刷新。保持非空 Space 不可删，全部分类记录真正清空后走原独立 Space 删除接口。
5. **检查共用扩展加载的关联影响。** Schedule、Dongle 与 GroupInfo 同样存在活动上下文依赖，应检查缺 Key 进入时的隔离边界；本次不迁移或改写现存项目 Key index/密钥。
6. **诊断日志。** 在 DEBUG 下记录 requested Site/Space/Network ID、actual Network ID、持久化 Switch 数、缓存数、筛选后数、删除结果与拒绝原因，不打印 Key、密码或凭据。

## 验证矩阵

- 目标缺 Key、目标有 1 个 Switch、其他子网无 Switch：目标页可见且可明确强制删除该记录。
- 其他 Space 使用相同 Switch ID/代理地址：删除目标不影响对方表、侧表、Group 或实体设备。
- 正常网络 Switch 删除与解绑行为保持；部分失败、取消、数据库写失败不误报成功。
- 活动筛选隐藏记录时有明确无匹配状态，可清除筛选；不同于真实空列表。
- 快速切换 Space 或后台加载回调晚到：不污染新页面与计数。
- 删除完成后重新进入，旧云端快照不能复活本地待确认删除的 Switch。
- 本地清空后 Space 删除可进入原 API；是否接受云端仍有旧记录，仍需真实服务端契约/现场验收。

本轮未构建、未真机测试；只生成分析文档。不得把本次分析称为已修复或已删除 Switch。
