# Up Down Light Group Vendor Subscription 分析与修复方案

## 背景

现象：

- 在组中添加 up down light。
- 通过组播发送 `SunricherVendorSet(function: .upDownLightUpRatio(...))`。
- 再进入单设备页或单设备 GET `SunricherVendorGet(function: .upDownLightUpRatio)`。
- 设备返回的 up ratio 没有变化。

当前 group 页组播 SET 路径：

- `GroupViewController.saveGroupUpRatioValue(_:)`
- 发送 `SunricherVendorSet(function: .upDownLightUpRatio(...))`
- 目标地址是 `group.address.address`
- 组播 SET 默认全部成功，不等待每个设备 ACK

## 代码事实

### 1. up/down ratio 的单设备 GET/SET 协议本身可用

SDK 已有：

- `SunricherVendorSet(function: .upDownLightUpRatio(UInt8))`
- `SunricherVendorGet(function: .upDownLightUpRatio)`
- `SunricherVendorStatus` 对 `0x53/0x02` 的解析

单设备 SET 通过 `node.sunricherVendorModel` 发给单设备 model；单设备 GET 也通过同一个 vendor model 获取真实值。

### 2. group control 发送的是 group address

当前组内 up ratio 保存逻辑发送：

- message: `SunricherVendorSet(function: .upDownLightUpRatio(UInt8(clampedValue)))`
- address: `group.address.address`

这要求设备上的 Sunricher vendor server model 已订阅该 group address，否则设备不会接收这条组播 vendor message。

### 3. 默认 group subscription 不包含 vendor model

SDK 默认 group subscription 配置是 `MeshLibManager.manager.groupSubscriptionModelIDs`，类型是 `[UInt16]`，只表示 SIG model id。

当前 App 在 `SiteViewController` 覆盖为：

- Generic OnOff Server
- Light Lightness Server
- Light CTL Temperature Server
- Light CTL Server
- Sensor Server
- Light LC Server

Sunricher vendor server model id 是 `UInt32`：

- company id: `0x0A78`
- model id: `0x0001`
- combined model id: `0x0A780001`

因此它无法通过现有 `[UInt16] groupSubscriptionModelIDs` 被默认加入。

### 4. 添加 group / 添加成员的当前链路同样不会补 vendor subscription

App 的 group member 添加路径主要通过：

- `GroupServer.groupAddNodes(...)`
- `group.getNodeAddMessageHandles(node:)`
- `node.getSunSmartSubscribeToGroupMessageHandles(group)`
- `node.getSubscribeToGroupMessages(group)`

`getSubscribeToGroupMessages(group)` 只遍历 `supportModels`，并筛选 `MeshLibManager.manager.groupSubscriptionModelIDs.contains(model.modelIdentifier)`。

由于 vendor model 不在这个 UInt16 列表里，所以不会生成 `ConfigModelSubscriptionAdd(group: to: vendorModel)`。

### 5. SDK 已支持 vendor model subscription message

`ConfigModelSubscriptionAdd(group: to: Model)` 会读取：

- `model.modelIdentifier`
- `model.companyIdentifier`

当 `companyIdentifier` 存在时，它会编码为 vendor model subscription 参数。因此不需要新增 Mesh 配置协议，只需要把应订阅模型集合补上 vendor model。

## 根因判断

当前最可能根因是：

> 添加 group 或添加 up down light 到 group 时，没有把设备的 Sunricher vendor server model 订阅到该 group address，导致 group address 的 `0xF00A78 / 0x53 / 0x02` SET 没有被设备接收。

用户提出的怀疑“是否未将 vendor model 绑定 group ID”基本成立。更精确地说，不是 AppKey bind，而是 vendor server model 的 group subscription 缺失。

## 修复目标

1. up down light 加入普通 group 后，其 Sunricher vendor server model 应订阅该 group address。
2. 组播 set up ratio 后，单设备 get up ratio 应能读到变化后的值。
3. 不扩大到所有 Sunricher 设备，避免让不需要 vendor group control 的设备额外订阅 vendor model。
4. 已存在的 group 也要有补偿路径，否则只修新建/新增成员不够。
5. 移出 group / 删除 group 时，相关 vendor subscription 应能被删除或被现有 unsubscribe all path 覆盖。

## 推荐方案

推荐采用“能力条件化的 vendor subscription 生成”。

### SDK 侧

在 `Node.getSubscribeToGroupMessages(_:)` 中补充逻辑：

- 先保持现有 SIG model subscription 逻辑不变。
- 若节点具备 up/down ratio 能力，且存在 `sunricherVendorModel`，且该 vendor model 尚未订阅该 group，则追加：
  - `ConfigModelSubscriptionAdd(group: group, to: sunricherVendorModel)`

判断条件放在 SDK 侧时不能依赖 App 层 `supportsUpDownRatioControl` 扩展。建议新增 SDK 内部能力判断，例如：

- `companyIdentifier == 0x0A78`
- `productIdentifier == 0x2491`
- `sunricherVendorModel != nil`

同时更新 `Node.subscribe(to:)` 的本地数据操作逻辑，让本地 mesh database 也能反映 vendor model 已订阅 group。这样 `ConfigModelSubscriptionStatus` 回来后 SDK 的本地模型状态一致。

### App 侧

保持 group 页组播 SET 逻辑不变：

- 继续发送到 `group.address.address`
- 继续默认组播成功
- 不做每个设备 ACK 判断

现有 `GroupServer.groupAddNodes`、恢复设备、sync devices 等路径会复用 `node.getSubscribeToGroupMessages(group)`，因此底层函数修复后能覆盖新建、编辑新增成员、恢复和补偿同步。

### 已有 group 的补偿

由于 `SyncDevicesCellModel` 的 group 配置成功判断依赖：

- `node.group == group`
- `node.getSubscribeToGroupMessages(group).count == 0`

修复 `getSubscribeToGroupMessages(group)` 后，已有 up down light group 会被识别为还有待同步的 vendor subscription。用户可通过现有 sync/repair 入口补发 subscription。

如果希望体验更主动，可以在进入 group control 页时检测 `upDownRatioNodes` 中是否存在缺失 vendor subscription，并提示/触发同步；这属于增强，不建议第一版做，避免把 group control 页变成隐式配置入口。

## 备选方案

### 方案 A：只在 group 页 set 前对每个成员单播 SET

优点：

- 不依赖 group vendor subscription。
- 可以立即验证每个设备响应。

缺点：

- 违背当前“组内通过组播发命令，默认全部成功”的设计。
- 设备多时慢，且会改变交互语义。
- 无法修复其他未来 vendor group control 的订阅根因。

不推荐。

### 方案 B：把 Sunricher vendor model 加入全局 group subscription

优点：

- 实现简单，所有 Sunricher vendor model 都能响应 group vendor message。

缺点：

- 影响面过大。
- 很多不需要 vendor group control 的设备也会多订阅 vendor model。
- `groupSubscriptionModelIDs` 当前是 `[UInt16]`，不能直接承载 vendor model；强行改成混合类型会影响 SDK 公共 API。

不推荐作为第一版。

### 方案 C：能力条件化订阅 up/down light 的 vendor model

优点：

- 只影响 `0x0A78 / 0x2491` up down light。
- 保持 group 页组播控制语义。
- 能覆盖新增成员、恢复、补偿同步等共享路径。
- 不需要改 ConfigModelSubscriptionAdd 协议编码。

缺点：

- 需要在 SDK 层增加 up/down light 能力判断，避免依赖 App 扩展。
- 已有 group 需要走一次同步/修复流程才会补上 vendor subscription。

推荐采用。

## 实施计划

1. 在 SDK 增加 up/down light 能力判断。
   - 文件：`Sources/NordicSigMeshSDK/MeshLib/Node/Node+SupportModels.swift` 或相邻 Node 扩展。
   - 条件：`companyIdentifier == 0x0A78 && productIdentifier == 0x2491 && sunricherVendorModel != nil`。

2. 修改 SDK 的 group subscription 消息生成。
   - 文件：`Sources/NordicSigMeshSDK/MeshLib/Node/Node+Messages.swift`
   - 在 `getSubscribeToGroupMessages(_:)` 末尾追加 vendor subscription message。
   - 只在 vendor model 尚未订阅该 group 时追加。

3. 修改 SDK 的本地订阅状态更新。
   - 文件：`Sources/NordicSigMeshSDK/MeshLib/Node/Node+Config.swift`
   - 在 `subscribe(to:)` 中同步处理 up/down light vendor model。
   - `unsubscribe(from:)` 当前按 `model.subscriptions.contains(group)` 删除所有模型订阅，原则上已经覆盖 vendor model。

4. 增加 SDK 测试。
   - 覆盖 `0x0A78 / 0x2491` 节点应生成 vendor subscription。
   - 覆盖非 up/down light 节点不生成 vendor subscription。
   - 覆盖 vendor model 已订阅时不重复生成。

5. 验证 App 构建。
   - 运行 iPhoneOS build。
   - 保持 App 侧 group up ratio SET 逻辑不变。

## 验收建议

硬件验证步骤：

1. 将 up down light 加入 group。
2. 确认配置过程会发送 vendor model subscription：
   - Config Model Subscription Add
   - company id `0x0A78`
   - model id `0x0001`
   - address 为目标 group address
3. 在 group control 页 set up ratio。
4. 进入单设备页触发 get up ratio。
5. 单设备返回值应等于 group set 的 up ratio。

旧 group 验证：

1. 对已有包含 up down light 的 group 执行现有 sync/repair。
2. 确认补发 vendor model subscription。
3. 再重复 group set + single get 验证。

