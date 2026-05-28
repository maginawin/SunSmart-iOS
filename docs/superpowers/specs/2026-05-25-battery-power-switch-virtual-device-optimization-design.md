# Battery Power Switch 虚拟设备详情页优化设计

## 背景

Battery Power Switch 已支持 pre-create，本地可以创建一个未关联真实设备的虚拟 BPS。当前虚拟设备进入详情页后仍复用真实 BPS 的部分运行态逻辑：顶部状态会因为没有电量更新时间显示 `Unknown`，底部 Enable 会因没有真实 node 提示失败，右上角菜单仍会出现与真实设备相关的项。

本次目标是收紧未关联虚拟 BPS 在详情页的行为：明确展示未关联状态，所有模拟控制静默不发命令，Enable 只更新本地数据库，菜单只保留 Edit 和 Delete。

## 已确认需求

- 未关联真实设备时，顶部 `Status` 从 `Unknown` 改为 `Unlinked`。
- 中间 8-key 模拟区域不发送任何命令，也不做任何提示。
- 底部 `Enable` switch 不发送任何命令，不做任何提示，不做任何修改阻拦，直接判断成功并更新到数据库。
- 虚拟设备右上角菜单仅保留：
  - `Edit`
  - `Delete`
- 虚拟 BPS 点击 `Delete` 时不保留删除确认弹窗，行为与虚拟 Kinetic switch 一致：直接本地删除，提示 `done!`，关闭详情页。

## 非目标

- 不实现虚拟 BPS 绑定真实设备的新流程。
- 不修改真实 Battery Power Switch 的同步、激活、TX Enable、LED Indicator 或 Key Config 协议。
- 不修改真实 Battery Power Switch 的菜单和控制行为。
- 不修改普通 Kinetic switch 详情页。
- 不新增 Auth 信息，不改依赖、target 配置或品牌资源。

## 方案选择

采用方案 A：在 `PJEightKeySwitchMonitorViewModel` 中集中定义未关联虚拟 Battery Power Switch 状态，`PJEightKeySwitchMonitorVC` 根据该状态分流行为。

不选择把判断散落在 VC 各事件里的方案，因为 Header、面板点击、长按弹窗、Enable、菜单、删除都需要识别同一状态，分散判断容易漏掉后续新增入口。

不选择给 `PJEightKeySwitchData` 做更完整运行态枚举，因为本轮只优化详情页运行行为，扩展模型层会扩大影响范围，且后续绑定流程尚未进入本期实现。

## 虚拟未关联识别边界

新增语义化状态，例如：

- `PJEightKeySwitchMonitorViewModel.isUnlinkedVirtualBatteryPowerSwitch`

判断原则：

- 当前详情页数据是 `PJEightKeySwitchData`。
- 该数据来自基础 switch 记录加 `PJEightKeySwitchRepository` metadata，因此能被 Switches 列表识别为 Battery Power Switch / 8-key switch。
- `proxyNodeAddress == nil` 或无法解析到真实 `proxyNode`。
- 不依赖 `batteryLevel`、`batteryLastUpdateTime`、`syncState` 或 `linkGroupAddress` 判断虚拟态。

这样 pre-create 出来的虚拟 BPS 会进入虚拟未关联模式；后续绑定真实设备并写入可解析的 `proxyNodeAddress` 后，自动回到现有真实 BPS 行为。

## Header 状态

虚拟未关联 BPS 的 Header 规则：

- `Status` 文案显示 `Unlinked`。
- 复用已有本地化 key：`neightkeyswitches_unlinked`。
- 状态颜色沿用当前 `Unknown` 的灰色，避免新增视觉规则。
- Battery 继续显示 `--`。
- Updated 继续显示 `--`。
- Refresh 按钮不显示，因为没有真实设备可读取电量。

真实 BPS 的 Header 仍按电量更新时间和电量值计算 `Normal`、`Low Battery`、`Unknown`。

## 中间模拟区域

虚拟未关联 BPS 的 8-key 面板只作为预览，不做控制：

- 短按任意 key：静默 no-op。
- 长按 dimming key：不弹 dimming popup。
- 长按 auto key：不弹 forced auto popup。
- 不调用 `PJEightKeySwitchVirtualGroupControlSender`。
- 不调用 `MeshAPI.sendMessage`。
- 不显示 failed、disabled 或其他提示。

如果 Enable 为 Off，面板视觉可以继续沿用 disabled 样式，但点击仍然静默，不显示 `neightkeyswitches_disabled_tip`。

真实 BPS 保持现有模拟控制行为：有 `linkGroupAddress` 时发送对应 Mesh 命令，没有可发送目标时按现有逻辑处理。

## 底部 Enable

虚拟未关联 BPS 切换底部 Enable 时：

- 不检查 `informationNode`。
- 不进入 `PJEightKeySwitchTxEnableFlow`。
- 不发送 Mesh / BLE 命令。
- 不显示 success 或 failed 提示。
- 不做修改阻拦。
- 直接更新 `switchData.enabled`。
- 尽量调用基础 switch 保存和 `PJEightKeySwitchRepository.shared.save(...)` 保存 metadata。
- 更新 `MeshNetworkManager.instance.switchs` 中相同 id 的数据。
- 发送 `switchsRefreshNotificationName`。
- 发送空间数据变化通知，沿用现有本地保存路径的 `spaceDataChangedNotificaitonName`。
- 立即刷新当前详情页 UI，视为成功。

如果本地数据库保存失败，本轮仍不弹错误提示，以满足“不做任何提示，直接判断成功”的产品边界。实现上只做 best-effort 保存，避免引入真实设备同步或阻塞行为。

真实 BPS 的 Enable 继续走 `PJEightKeySwitchTxEnableFlow` 和现有同步逻辑。

## 右上角菜单

虚拟未关联 BPS 的右上角菜单只展示：

- `Edit`
- `Delete`

菜单权限仍尊重当前 space 的操作权限：

- 只有包含 `.edit` 时展示 `Edit`。
- 只有包含 `.delete` 时展示 `Delete`。

虚拟未关联 BPS 不展示：

- `Information`
- `Identify`
- 任何真实设备相关菜单项。

已绑定真实 BPS 继续沿用现有菜单：按权限展示 Edit / Delete，真实设备时可展示 Information，Identify 本轮不改。

## Delete 行为

虚拟未关联 BPS 点击 `Delete` 时：

- 不弹删除确认。
- 不检查 Mesh 是否 connected。
- 不进入 `SyncDevicesViewController`。
- 直接调用现有本地删除路径，例如 `MeshNetworkManager.instance.deleteSwitch(switchData:)`。
- 删除基础 switch 记录。
- 删除 `PJEightKeySwitchRepository` metadata。
- 从 `MeshNetworkManager.instance.switchs` 中移除。
- 发送 `switchsRefreshNotificationName`。
- 发送空间数据变化通知。
- 显示 `done!`。
- 短暂延迟后关闭详情页。

这个行为与未使用过的虚拟 Kinetic switch 删除保持一致。

真实 BPS 删除仍按现有逻辑：如果存在需要同步的数据，继续走同步删除；无同步数据时走本地删除。

## Edit 行为

虚拟未关联 BPS 的 `Edit` 继续进入 `PJPreAddEightKeySwitchesVC(space:switchData:)`。

编辑页继续保留 LINK 入口：

- 未关联时显示 `LINK`。
- 已关联真实设备后显示 `LINKED`。
- 本轮不实现 LINK 后续绑定流程。

编辑保存仍沿用已实现的 BPS pre-create / edit 持久化逻辑。

## 错误处理

- 中间模拟区域在虚拟未关联模式下没有错误态，所有交互静默 no-op。
- Enable 在虚拟未关联模式下没有错误提示，保存失败也不阻拦当前 UI 成功状态。
- Delete 使用本地删除路径，若底层删除没有返回错误，则沿用现有 `done!` 成功反馈。
- Refresh 按钮在虚拟未关联模式下隐藏，因此不会出现读取失败提示。

## 测试计划

静态检查：

- 未关联虚拟 BPS 的 Header 状态返回 `neightkeyswitches_unlinked`。
- 未关联虚拟 BPS 不显示 Refresh 按钮。
- 未关联虚拟 BPS 的 key tap / long press 不调用 `MeshAPI.sendMessage`。
- 未关联虚拟 BPS 的 Enable 不创建 `PJEightKeySwitchTxEnableFlow`。
- 未关联虚拟 BPS 菜单只构造 Edit / Delete。
- 未关联虚拟 BPS Delete 不进入 `SyncDevicesViewController`。
- 已绑定真实 BPS 仍走现有真实设备路径。

手动 QA：

- 创建虚拟 Battery Power Switch 后进入详情页，顶部 Status 显示 `Unlinked`。
- 点击中间任意 key，无提示、无弹窗、无设备控制。
- 长按 dimming / auto 区域，无提示、无弹窗。
- 切换底部 Enable，UI 立即更新；返回列表再进入后状态保持。
- 右上角菜单仅展示 Edit / Delete。
- 点击 Delete 直接提示 `done!` 并关闭详情页，列表中该虚拟 BPS 消失。
- 已绑定真实 Battery Power Switch 的状态、菜单、Enable 同步、模拟控制不受影响。

构建验证：

- 直接执行项目推荐命令：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## 影响范围

预计修改集中在：

- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`

不需要修改本地化资源，因为已有 `neightkeyswitches_unlinked`。不需要修改 target 配置、依赖或品牌资源。
