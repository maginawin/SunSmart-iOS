# Content Display 云端同步分析

## 结论

当前 App 的 `Site - Space - More - Content Display` 页面配置没有上传到云端同步。

该页面目前只有一个配置项：`displayDeviceNamePrefix`，即是否显示设备名前缀。用户切换开关后只更新当前 `SpaceData` 对象并调用 `space.save()` 保存到本地数据库，没有触发空间数据变更通知，也没有直接加入 `CloudSynchronizationManager` 的同步队列。

即使后续由其他入口触发了 `syncSpace` 或 `syncSite`，当前 `SpaceData.export()` 生成的上传 payload 也没有包含 `displayDeviceNamePrefix` 字段，因此该配置不会随现有云端同步接口上传。

## 代码链路

### 页面入口

- `SunSmart/Main/Space/Controller/SpaceMoreViewController.swift`
  - `.contentDisplay` 菜单项展示为 `content_display`
  - 点击后创建 `ContentDisplayViewController(space: space)`

### 页面配置项

- `SunSmart/Main/Space/Controller/ContentDisplayViewController.swift`
  - `options` 只有 `.deviceNameDisplay`
  - cell 初始状态读取 `space.displayDeviceNamePrefix`
  - 开关变化后执行：
    - `self.space.displayDeviceNamePrefix = isOn`
    - `self.space.save()`

这里没有：

- 更新 `space.lastUpdate`
- 发送 `spaceDataChangedNotificaitonName`
- 调用 `CloudSynchronizationManager.shared.addSynchronizationHandle(...)`

### 本地持久化

- `SunSmart/Common/Data/SpaceData.swift`
  - `displayDeviceNamePrefix` 是 `SpaceData` 字段，默认值为 `true`
- `SunSmart/Common/Data/Database.swift`
  - spaces 表包含 `displayDeviceNamePrefix` 列
  - `SpaceData.load(...)` 会从数据库读取该字段
  - `SpaceData.save()` 会把该字段写入数据库

因此该配置在本机持久化是完整的。

### 自动云同步触发条件

- `SunSmart/Main/Space/Controller/SpaceViewController.swift`
  - 监听 `spaceDataChangedNotificaitonName`
  - 收到通知后更新 `space.lastUpdate`
  - 再根据变更类型触发 `syncSpace` 或 `syncSite`

项目里常见的空间数据变更入口会通过 `NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType...)` 触发这套逻辑。

但 `ContentDisplayViewController` 的开关保存没有发送这个通知，所以不会走这条自动同步链路。

### 云端上传 payload

- `SunSmart/Common/Cloud/CloudSynchronizationManager.swift`
  - `.syncSpace` 最终调用 `space.export()`
  - 生成 `.spaceUpload(siteId: space.siteId, spaceData: await space.export())`
- `SunSmart/Common/Network/NetowrkReqeustApi.swift`
  - `spaceUpload` 路径为 `/sitespace/sync/spaceprops`
  - 参数为 `["siteId": siteId, "spaces": [spaceDatas], "userId": ...]`
- `SunSmart/Common/Data/ExportData.swift`
  - `SpaceData.export()` 导出了 `uuid`、`spaceName`、`imageId`、`source`、`createTimestamp`、`updateTimestamp`、`deviceBlinkMode`、`triggerZones`、节点、组、开关、场景、日程等
  - 没有导出 `displayDeviceNamePrefix`

所以即使其他操作触发空间上传，当前 payload 也不会包含 Content Display 的配置。

### 云端导入

- `SunSmart/Common/Data/ImportData.swift`
  - `SpaceData.update(spaceJsonData:)` 会读取 `deviceBlinkMode`、`triggerZones` 等字段
  - 没有读取 `displayDeviceNamePrefix`

这说明当前云端数据恢复/分享导入流程也不会还原该配置。

## 影响

- 当前设备上切换 Content Display 后，本地立即生效，并能随本地数据库保留。
- 换设备、重新导入、云端拉取空间数据、分享空间同步时，该配置不会被同步。
- 因为没有更新 `lastUpdate`，该开关变化本身也不会让空间显示为“需要上传云端”。

## 如需支持云同步

最小改动方向：

1. 在 `ContentDisplayViewController` 保存开关时，按现有空间数据变更模式更新 `lastUpdate` 或发送 `spaceDataChangedNotificaitonName`。
2. 在 `SpaceData.export()` 中加入 `displayDeviceNamePrefix`。
3. 在 `SpaceData.update(spaceJsonData:)` 中读取该字段，缺省保持 `true` 以兼容旧云端数据。
4. 验证 `/sitespace/sync/spaceprops` 后端是否接受并原样返回新增字段；如果后端字段白名单拦截，需要同步后端协议。
