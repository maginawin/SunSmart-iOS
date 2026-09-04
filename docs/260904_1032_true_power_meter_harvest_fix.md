# True Power Meter 能耗采集展示修复总结

## 结论

L12 的 Mesh 采集链路正常。App 日志中的 Sensor Status 来自 L12 能耗元素 `0x0D06`，包含：

- Precise Total Device Energy Use：`0.283 kWh`
- Active Energy Loadside：`0.313 kWh`

采集完成后，App 会把这两个值归并到主节点 `0x0D04`，并在用户选择 Use incomplete data 时，把 L12 作为成功设备写入本地静态能耗快照。原页面显示 `0.000 kWh` 的原因是 True power meter 分支在 Space 和 Group 视图中主动把展示变量改成 0，同时在 Device 视图中清空设备列表；它没有覆盖节点值或已保存快照。

修复后，L12（PID `0x2304`）属于 True power meter，Space、Group、Device 三种视图都基于同一份筛选后的快照展示真实数值。

## 修复内容

1. 增加统一计量类型策略，当前 True power meter PID 为 `0x2302`、`0x2303`、`0x2304`、`0x2305`、`0x2801`、`0x2802`。
2. All、True power meter、Manual data entry 改为互斥筛选：
   - All：全部符合能耗统计条件的灯具。
   - True power meter：支持真实功率计量的灯具。
   - Manual data entry：其余依靠额定功率数据计算的灯具。
3. 在 Controller 层先过滤最新和上一次快照，再把相同口径的数据传给 Space、Group、Device，移除各视图的占位归零逻辑。
4. Group 饼图按当前筛选后的设备重新计算总量、占比和分组项。
5. 新采集快照写入计量类型；历史快照没有该字段时，按已保存的 Product ID 回退分类，因此现有 L12 历史数据仍可显示。
6. 新策略文件加入五个共享 App Target，未修改 SDK、资源、本地化、约束或服务器协议。

## 本地保存与服务器同步边界

静态能耗快照保存在本地 SQLite 的 `energyStaticDatas` 表中，设备数组编码到 `deviceEnergys` 字段。L12 本次成功响应会保存真实采集值，True power meter 的 UI 筛选只创建展示用统计对象，不会回写数据库。

`syncSpace` 调用 `SpaceData.export()` 生成 `/sitespace/sync/spaceprops` 的上传数据。当前导出包含设备配置中的 `ratedPowerPhases`，但不包含：

- `energyStaticDatas` 本地静态能耗快照；
- `preciseTotalDeviceEnergyUse`；
- `totalDeviceEnergyUse`。

因此，原 UI 的 `0.000 kWh` 不会污染服务器同步数据。需要同时明确：目前静态能耗采集历史本身也不会同步到服务器；HTTP 200 只证明 Space 配置上传成功，不能证明能耗快照已上传。

## 验证结果

- 能耗筛选策略测试：通过。
- UI 接线与五 Target membership 合约测试：通过。
- Xcode 工程文件格式检查：通过。
- generic iOS device Debug 构建：SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 全部通过。
- 构建只出现工程已有资源重复、旧 API 等告警，没有本次修复引入的错误。

## 待真机验收

使用包含 L12 的同一 Space 重新进入 Energy Data，依次检查 All、True power meter、Manual data entry，并覆盖 Space、Group、Device 三种视图。按本次 App 日志对应快照，True power meter 的 Space 总能耗至少应包含 L12 的 `0.283 kWh`，而不是固定显示 0；最终总计还取决于该筛选类别下其他成功设备的数据。
