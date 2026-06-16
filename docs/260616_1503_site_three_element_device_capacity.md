# 同一 Site 内 3-Element 设备容量分析

## 结论

- 单个普通 space 的 App 添加入口最多允许 300 台设备，不按 element 数折算。
- 同一个 site 下的多个 space 共享同一个 meshUUID 和 unicast 地址池。
- 在干净 site、每台设备正好 3 elements、地址连续且服务器能持续分配地址的前提下，同一 site 理论最多可容纳 10922 台 3-element 设备。
- 如果设备是“至少 3 elements”，则 10922 是上限；实际 element 数大于 3 时，最大设备数按可用 unicast 地址数除以实际 element 数向下取整。

## 计算依据

Bluetooth Mesh unicast 地址范围在 SDK 中定义为：

- 最小 unicast address：0x0001
- 最大 unicast address：0x7FFF
- 总 unicast 地址数：32767

App 创建 site 时会把本机 provisioner 放在 0x0001，因此干净 site 中可给真实设备使用的地址约为：

- 32767 - 1 = 32766

3-element 设备每台占用 3 个连续 unicast 地址，因此理论最大值：

- floor(32766 / 3) = 10922

## 代码证据

- `SpaceData.maxDevicesCount` 默认值为 300；普通设备添加页在 `viewDidLoad` 中读取该值，并在选择/添加时用当前 mesh 的 `realNodes.count` 做数量拦截。
- 普通 space 添加入口在添加前按 `devices.reduce(... + device.elementCount)` 估算所需地址数，并通过 `MeshAPI.getNumberOfAvailableUnicastAddresses(meshUUID: space.meshUUID)` 判断当前 site 的可用 unicast 地址是否足够。
- site 级添加入口同样使用 `site.meshUUID` 计算可用 unicast 地址，说明地址池是 site 级。
- `SiteData.addSpace` 是在同一个 `meshUUID` 下新增 subnetwork；数据库加载 `SpaceData` 时也把 `meshUUID` 设置为 `siteUUID`，所以同一 site 内所有 space 共享同一个 mesh address space。
- SDK 的可用 unicast 地址计算会从 local provisioner 的 `allocatedUnicastRange` 中排除已有 node elements、exclusions 和已预分配地址。
- SDK 分配设备主地址时要求能够容纳连续的 `elementsCount` 个地址；因此碎片化时，单纯“可用地址总数足够”不一定代表一定能继续添加 3-element 设备。

## 实际限制说明

单个 space 实际可通过普通 Add Device UI 添加的 3-element 设备数仍是 300 台，因为 App 先执行 `space.maxDevicesCount` 检查。

如果同一个 site 下创建多个 space，App 侧没有在当前代码中看到 site 级 space 数量上限；因此 site 总量会继续受共享 unicast 地址池限制。要达到 10922 台 3-element 设备，至少需要 37 个 space 才能绕开单 space 300 台限制。

site 级 gateway 添加入口没有看到同样的 `maxDevicesCount` 拦截，但它只允许 gateway 类型，并同样消耗 site 的 unicast 地址池。

## Caveat

10922 是当前 App + 本地 SDK 代码可推出的理论上限，不等同于云端一定允许。`applyAddress(siteId:type:number:)` 的服务器侧配额、账号策略、产品策略或线上数据迁移规则不在本地仓库内，若服务器限制更小，实际可添加数量会以服务器返回为准。
