# PID 0x2057 首次进入 Group Members 不显示图标分析

## 结论

根因不是设备第一次加入 Group 后才获得图标，也不是 `productId = 2057` 无法解析。

该设备配置的 `iconCategory` 是 `MWSensorLighting`。工程当前只提供了以下两种资源：

- `device_MWSensorLighting`
- `device_offline_MWSensorLighting`

但 Group Members 页面还存在第三种“待同步”显示状态，会按统一命名规则请求：

- `device_unsync_MWSensorLighting`

这个资源在当前工程中不存在。首次添加到 Space 的节点仍有 Group/Profile 数据待同步时，页面先设置正常图标，随后又使用不存在的待同步图标覆盖；`UIImage(named:)` 返回 `nil`，因此图标区域变为空白。

设备成功加入过一次 Group 后，相关 Profile/订阅状态被同步，`needSyncGroupData` 重新计算为 `false`。页面不再执行待同步图标覆盖，Cell 先前设置的正常图标 `device_MWSensorLighting` 得以保留，因此再次进入 Members 时能够展示图标。

## 源码证据

### 1. 设备配置决定三种图标名称

`MeshDeviceConfigInfo` 根据 `iconCategory` 生成正常、离线和待同步三个资源名：

- `SunSmart/Common/Mesh/Device/MeshDeviceConfigInfo.swift:30-40`
- `iconCategory = MWSensorLighting` 对应：
  - 正常：`device_MWSensorLighting`
  - 离线：`device_offline_MWSensorLighting`
  - 待同步：`device_unsync_MWSensorLighting`

`Node.iconName`、`Node.offlineIconName`、`Node.unsyncIconName` 直接使用以上映射：

- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:2358-2381`

### 2. Members Cell 先设置正常图标

Group Members 使用 `DevicesViewCell`：

- `SunSmart/Main/Group/Controller/GroupMembersViewController.swift:653-657`

设置 `cell.device` 后，Cell 在 Key Bind 完成时先加载 `device.elControllerLightsIconName`；对 PID `0x2057`，该值最终回落到正常的 `node.iconName`：

- `SunSmart/Main/Device/View/DevicesViewCell.swift:32-48`
- `SunSmart/Common/Data/Node+ELControllerRxTx.swift:55-65`

因此正常资源本身是可解析的，空白不是第一次赋值造成的。

### 3. 待同步状态随后覆盖正常图标

Members 页面在节点在线、Key Bind 完成且 `needSyncGroupData == true` 时，再次赋值：

- 首次创建 Cell：`SunSmart/Main/Group/Controller/GroupMembersViewController.swift:678-680`
- 节点刷新 Cell：`SunSmart/Main/Group/Controller/GroupMembersViewController.swift:548-550`

这次请求的是 `node.unsyncIconName`，即 `device_unsync_MWSensorLighting`。资源不存在时，赋值结果是 `nil`，刚才已经成功设置的正常图标也被清空。

### 4. 首次添加设备为什么容易进入待同步分支

`needSyncGroupData` 由 `getNeedSyncGroup()` 计算并缓存：

- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:2428-2437`
- `SunSmart/Common/Data/Node+SyncData.swift:655-669`

未加入 Group 的新节点只要仍有默认 Profile 状态需要归一化，就会返回待同步。例如：

- Power Up State 尚未恢复为 `.restore`
- Vendor + Light LC 设备的 Manual Override 尚未配置为永久启用

对应判断位于：

- `SunSmart/Common/Data/Node+SyncData.swift:823-842`

要区分本次真机具体是上述哪一项，需要输出该节点的 `getNodeSyncProfiles(group: nil)` 结果；但这不影响图标空白的直接根因，因为任何原因只要让 `needSyncGroupData` 为 `true`，都会触发缺失资源覆盖。

### 5. 加过一次 Group 后为什么恢复

新增成员会以 `.memberAdded` 上下文强制执行完整 Group Profile 同步：

- `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:139-169`
- `SunSmart/Common/Data/Node+SyncData.swift:11-27`

同步消息完成后会更新节点缓存并清除同步状态缓存：

- `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:2596-2614`

当节点状态达到目标值后，后续 `getNeedSyncGroup()` 返回 `false`。Members 页面不再覆盖待同步图标，因此正常图标重新可见。

## 资源对照

| `iconCategory` | 正常 | 离线 | 待同步 | 结果 |
| --- | --- | --- | --- | --- |
| `Lighting` | 存在 | 存在 | 存在 | 三种状态均可展示 |
| `MWSensorLighting` | 存在 | 存在 | **缺失** | 待同步状态显示空白 |

资源检查结果：

- `SunSmart/Assets.xcassets/Device/device_MWSensorLighting.imageset`：存在，含 1x/2x/3x
- `SunSmart/Assets.xcassets/Device/device_offline_MWSensorLighting.imageset`：存在，含 1x/2x/3x
- `SunSmart/Assets.xcassets/Device/device_unsync_MWSensorLighting.imageset`：不存在
- `SunSmart/Assets.xcassets/Device/Icon/Lighting/device_unsync_Lighting.imageset`：存在，可工作的对照项

Git 历史也显示，2026-07-22 的 `d413b966` 只新增了 `MWSensorLighting` 的正常和离线资源，没有新增待同步资源。

## 影响范围

该问题不只存在于首次选择 Members 的 Cell。

以下页面都直接用 `UIImage(named: node.unsyncIconName)` 覆盖已有图标，且没有资源缺失回退：

- Group Members 首次加载与节点刷新
- Group 设备列表首次加载与节点刷新
- Schedule Devices 列表

相关位置：

- `SunSmart/Main/Group/Controller/GroupMembersViewController.swift:548-550,678-680`
- `SunSmart/Main/Group/Controller/GroupViewController.swift:1562-1564,1835-1837`
- `SunSmart/Main/Timed/View/ScheduleDevicesView.swift:328`

共享的 `SunSmart/Assets.xcassets` 被 `SunSmart`、`Archipelago`、`SylSmart`、`SLG Sync Plus` 四个 target 引用，因此资源缺失会影响所有使用该设备配置的品牌 target。

## 修复建议

### 首选最小修复

补充完整的 `device_unsync_MWSensorLighting.imageset`，包含 1x、2x、3x，并采用已确认的待同步视觉稿。

这样可以保持现有图标状态命名约定，也能一次覆盖 Group Members、Group 设备列表和 Schedule Devices。

### 防御性增强

待同步资源加载失败时，不应把已经成功加载的正常图标覆盖为 `nil`。可以增加统一图标解析回退：

1. 优先使用具体类别的待同步图标；
2. 缺失时回退到通用 `device_unsync_Lighting`，保留“待同步”语义；
3. 通用待同步资源仍不存在时，再回退到正常图标。

资源补齐解决当前 PID，防御性回退可以避免服务器以后新增 `iconCategory` 时再次出现整个图标消失。

不建议通过强行清除 `needSyncGroupData` 解决显示问题，因为该状态代表真实的 Profile、订阅、场景、日程等同步差异，清除后会掩盖业务状态。

## 建议验收

修复后至少验证以下状态：

1. PID `0x2057` 第一次添加到 Space 后，进入 Group Members，待同步图标可见。
2. 成功加入 Group 后再次进入 Members，正常图标可见。
3. 设备离线时，离线图标可见。
4. Group 同步失败或仍有待同步数据时，待同步图标可见且不为空。
5. `SunSmart`、`Archipelago`、`SylSmart`、`SLG Sync Plus` 四个 target 完成 generic iPhoneOS 构建。
6. 真机确认首次入网、入组成功、入组失败三条 UI 状态链路。

## 验证边界

本次只做源码、资源目录和 Git 历史的静态分析，没有修改业务代码或资源，也没有执行构建和真机验证。

