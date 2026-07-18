# Site / Space Network Key 使用与删除后分配分析

## 结论

当前 App 把一个 Site 建模为同一个 Mesh Network：

- Site 使用该 Mesh Network 的 Primary Network Key。
- 每新增一个 Space，都会在同一个 Mesh Network 下创建一个新的 Subnet，并同时生成一对新的 Network Key 与 Application Key。
- `SpaceData.meshNetworkId` 保存的是该 Space 对应 Network Key 的 `networkId`，进入 Space 时 App 用它切换当前 Subnet。
- 删除 Space 时，正常路径会删除对应的 Application Key、Network Key 和子网持久化数据。
- 再新建 Space 时会重新随机生成新的 Network Key 与 Application Key，不会复用已删除 Space 的密钥内容。

对于“Space 1、2、3，删除 Space 2，再创建 Space 4”的场景，典型分配如下：

| 对象 | Network Key Index | Key 内容 |
| --- | ---: | --- |
| Site Primary Network | 0 | Site 创建时随机生成 |
| Space 1 Subnet | 1 | Space 1 创建时随机生成 |
| Space 2 Subnet | 2 | Space 2 创建时随机生成，删除 Space 2 后移除 |
| Space 3 Subnet | 3 | Space 3 创建时随机生成 |
| Space 4 Subnet | 4 | Space 4 创建时重新随机生成 |

因此 Space 4 不会复用 Space 2 的 Network Key，也不会复用 index 2；它会创建全新的 key，并通常取得 index 4。配套的 Application Key 也按相同方式生成和删除。

## 代码链路

### 1. Site 使用 Primary Network Key

`SiteData.add(name:)` 创建一个新的 Mesh Network，并把 `mainNetworkKey.networkId.hex` 保存到 `SiteData.meshNetworkId`。

进入 Site 页面时，如果当前不是该 Site 的 Primary Network，App 会用 `site.meshNetworkId` 重新切换到主网络。

Site 云端导出也明确选择 `networkKeys.first(where: { $0.isPrimary })` 及其绑定的 Application Key，分别输出为 `netKey` 和 `appKey`。

### 2. 每个 Space 创建独立 Subnet key pair

`SiteData.addSpace(...)` 调用：

`MeshNetworkManager.addSubnetwork(meshUUID:networkKeyName:applicationKeyName:)`

SDK 的 `addSubnetwork(...)` 使用两个独立的随机 128-bit 默认参数，分别创建 Network Key 与 Application Key，再将 Application Key 绑定到新 Network Key，最后保存 Mesh Network。

App 把新 Network Key 的 `networkId.hex` 写入 `SpaceData.meshNetworkId`。进入 Space 时，`SpaceViewController` 使用该值切换 Subnet。因此 Space 的设备配置与业务通讯使用该 Space 当前子网对应的 key。

Space 云端导出会按 `space.meshNetworkId` 找到对应 Network Key，再找绑定到它的 Application Key，并输出 `netKey`、`appKey` 和 `appKeyIndex`。

### 3. 删除 Space 会删除对应 key pair

Space 删除入口最终调用 `SpaceData.delete()`。该方法调用：

`MeshNetworkManager.removeSubnetwork(meshUUID:networkId:)`

SDK 按 `networkId` 找到非 Primary Network Key，然后先强制移除绑定的 Application Key，再强制移除 Network Key，删除该 Subnet 的持久化数据并保存 Mesh Network。

### 4. 新 key index 不填补中间空洞

SDK 的 `nextAvailableNetworkKeyIndex` 和 `nextAvailableApplicationKeyIndex` 都明确不搜索空洞，而是返回当前数组最后一个 key 的 index 加 1。

因此删除中间的 Space 2 后，Network Key 列表从 `[0, 1, 2, 3]` 变为 `[0, 1, 3]`；创建 Space 4 时从最后一个 index 3 继续分配，得到 index 4，而不是补回 index 2。

这里需要区分两件事：

- 删除中间 key：index 空洞不会被复用。
- 如果删除的恰好是最后一个 key，下一次创建时可能再次取得相同的 index；但 key 内容仍会重新随机生成，因此不是复用旧 Network Key。

Space 的显示名称或编号不参与 key index 计算。即使新 Space 命名为 `Space 4`，真正分配规则仍是“当前最后一个 key index + 1”。

## 对 Kinetic Switch / Battery Power Switch 的影响

删除一个 Space 时，SDK 只是从 `networkKeys` / `applicationKeys` 数组中移除该 Space 对应的 key 对象，不会修改其他现存 key 对象的 `index`。

例如 Space 3 原本使用：

- Network Key Index：3
- Application Key Index：3

删除 Space 2 后，Space 3 的 Network Key Index 和 Application Key Index 仍然都是 3，不会因为它在数组中的位置从第三个子网变成第二个子网而重排为 2。

因此：

- Kinetic Switch 的 `SwitchKey` 本地动作模型不直接保存 NetKey Index；配置代理节点 publication 时使用 `MeshNetworkManager.instance.currentApplicationKey`。只要仍处于原 Space，publication 使用的 Application Key Index 不变。
- Battery Power Switch 的按键协议配置实际写入的是 `appKeyIndex`，由 `MeshNetworkManager.instance.currentApplicationKey.index` 生成。删除其他 Space 不会改变本 Space 的 Application Key Index，因此设备中已经配置的 index 不会因此失效。
- Application Key 仍绑定到原 Network Key，二者不会因删除前面的 Space 而被重新编号。

所以用户担心的“删除 Space 2 导致 Space 3 的 key index 从 3 变成 2，继而让开关配置失效”在当前删除实现中不会发生。

只有删除开关自身所属的 Space，或通过异常导入、手工修复、Key Refresh 等其他流程替换了该 Space 的实际 key 数据时，原设备配置才需要另行评估。单纯删除同一 Site 下的其他 Space 不会触发这种变化。

## 边界与风险

- App 当前忽略了 `MeshNetworkManager.removeSubnetwork(...)` 的 Bool 返回值。正常路径会完成删除，但如果 SDK 删除异常，UI/Space 数据仍可能继续被删除，从而留下孤立 key；当前没有显式失败提示或补偿逻辑。
- 上述 index 示例以正常、连续创建且无异常导入的 Site 为前提。若 Mesh 数据曾从云端导入、修复或存在不规则 key 顺序，精确的新 index 仍以 SDK 当前数组最后一个 key 的 index 加 1 为准。
- Network Key Index 只是 12-bit 标识，不是密钥本身。即使某次删除末尾 Space 后 index 被再次使用，新生成的 128-bit key 与 `networkId` 仍是新的。

## 主要代码证据

- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`：Site 创建、Space 创建与 Space 删除入口。
- `SunSmart/Main/Site/Controller/SiteViewController.swift`：Site 主网络切换、Space 新增和删除路径。
- `SunSmart/Main/Space/Controller/SpaceViewController.swift`：进入 Space 后按 `meshNetworkId` 切换子网。
- `SunSmart/Common/Data/ExportData.swift`：Site Primary key 与 Space Subnet key 的云端导出规则。
- `SunSmart/Common/Data/ImportData.swift`：Site / Space 从云端 key 数据恢复 `meshNetworkId` 的规则。
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/MeshNetwork/MeshNetwork+Custom.swift`：Subnet key pair 的创建与删除。
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Mesh API/MeshNetwork+Keys.swift`：Key index 只按最后一个 index 加 1、不填补空洞的规则。
