# Kinetic Switch 色温订阅修复总结

## 实施结果

已按用户确认后的方案完成聚焦修复：

- 仅阻止新创建的 Kinetic Switch 为单色调光灯生成 CCT 虚拟组订阅；
- 不处理已经错误配置的设备或历史订阅；
- 既有配置由用户删除 Switch 后重新添加；
- Default (4 key) 与 Scene Panel (4 key) 的按键映射、Scene Recall 和虚拟组分配均未修改。

## 代码改动

本地 SDK：

`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`

### 新增 CCT Level Model resolver

文件：

`Sources/NordicSigMeshSDK/MeshLib/Node/CctLevelModelResolver.swift`

resolver 只有在存在 Temperature 元素时才查询该元素的 Generic Level Model。没有 Temperature 元素时直接返回空，不再使用任何亮度 Level Model 作为回退。

### 收紧 Node 能力解析

文件：

`Sources/NordicSigMeshSDK/MeshLib/Node/Node+SupportModels.swift`

`ctlTemperatureLevelModel` 改为通过 resolver 从 `temperatureModel.parentElement` 查找 `0x1002`：

- 色温灯：继续解析到 Temperature 元素上的 Generic Level Server；
- 单色调光灯：因为没有 Temperature Model，返回空；
- 亮度 `levelModel` 逻辑保持不变。

### 新增 standalone 回归测试

文件：

`Tests/Standalone/CctLevelModelResolverTests.swift`

覆盖：

- 单色灯没有 Temperature 元素时，不能得到 CCT Level Model，且不能执行 Level Model 查询；
- Temperature 元素存在时，返回该元素对应的 Level Model；
- Temperature 元素缺少 Level Model 时返回空。

## TDD 证据

### RED

首次只添加测试并执行编译，失败信息为：

`cannot find 'CctLevelModelResolver' in scope`

说明测试在生产 resolver 实现前确实失败。

### GREEN

新增 resolver 并接入 `Node.ctlTemperatureLevelModel` 后运行：

`CctLevelModelResolverTests passed`

exit code 为 0。

## 消费路径复核

`MeshEnOceanProxyServer.getEnOceanSubscriptionMessageHandles` 未修改：

- `dimUp / dimDown` 继续使用 `node.levelModel`；
- `cctUp / cctDown` 只在 `node.ctlTemperatureLevelModel` 非空时生成订阅。

因此：

- L1、L2 仍会把 Temperature 元素的 `0x1002` 订阅到 CCT 虚拟组；
- L3 不再为 CCT 动作生成 Subscription Add；
- 三盏灯的亮度 Dim Up / Dim Down 行为不受影响。

App 的 `DeviceSwitchData.switchKeys` 也未修改：

- Default (4 key) 的 Cooler / Warmer 继续使用 `subLinkGroupAddress`；
- Scene Panel (4 key) 的 Cooler / Warmer 同样继续使用 `subLinkGroupAddress`。

## 编译验证

以下构建均使用：

- Debug
- `iphoneos`
- `generic/platform=iOS`
- `CODE_SIGNING_ALLOWED=NO`
- 本地 `NordicSigMeshSDK`

结果：

- `SunSmart`：`BUILD SUCCEEDED`
- `Archipelago`：`BUILD SUCCEEDED`
- `SLG Sync Plus`：`BUILD SUCCEEDED`
- `SylSmart`：`BUILD SUCCEEDED`

## 未覆盖与真机验收

本轮没有真实 Kinetic Switch 和 L1 / L2 / L3 Mesh 设备，因此不能把自动化测试或编译成功表述为完整业务链验收。

真机需要先删除旧 Switch，再分别使用 Default (4 key) 和 Scene Panel (4 key) 重新添加并验证：

1. 创建日志中 L1、L2 出现 CCT 虚拟组的 Temperature Level `0x1002` Subscription Add。
2. 创建日志中 L3 不出现 CCT 虚拟组的 `0x1002` Subscription Add。
3. 长按 Cooler / Warmer 时，仅 L1、L2 色温变化，L3 亮度保持不变。
4. 长按 Dim Up / Dim Down 时，L1、L2、L3 亮度均正常变化。
5. Default Panel 的 Scene A / B 与 Scene Panel 的 Scene A / B / C / D 均正常。
