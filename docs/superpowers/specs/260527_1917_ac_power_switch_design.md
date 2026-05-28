# AC Power Switch 设计说明

## 背景

AC Power Switch 是 2422K8N 系列的常供电开关设备，Company ID 固定为 `0x0A78`，Product ID 覆盖 `0x2A11` 和 `0x2A12`。它与现有 Battery Power Switch 在 8-key Profile、按键配置、目标组订阅、TX Enable、LED Indicator 等功能上基本一致，但供电形态不同：AC 常在线、无电池模型、不需要低功耗激活窗口，也不应在添加后主动断开 Proxy。

协议参考：

- `protocols/2422K8N-4SC-AC-US.md`
- `protocols/260527_1827_2422K8N_battery_vs_ac_protocol_diff.md`
- `protocols/0x2A11.json`
- `protocols/0x2A12.json`

## 目标

- 在 Switches 添加弹窗中新增 `AC Power Switch` 入口，位于 `Battery Power Switch` 右侧。
- 支持创建未绑定的 AC Power Switch 虚拟开关，并持久化其设备族。
- 支持 AC Power Switch 配网、绑定、恢复/替换设备绑定、默认配置、同步和删除。
- 复用现有 Battery Power Switch 的 Profile、按键配置、目标组订阅和 8-key UI 能力。
- AC Power Switch 不显示电池电量，不读取 Generic Battery，不主动断开 Proxy。
- AC Power Switch 在 SAVE、启用/禁用、同步自有配置时不等待设备激活。
- 已绑定 AC Power Switch 监控页顶部居中展示 `Online` 或 `Offline`；未绑定虚拟 AC 继续展示 `Unlinked`。
- AC、Battery、动能开关共用现有 16 个 switch 总量上限。

## 非目标

- 不新增 RTC 黑匣子、RTC fault 展示或 Time Server 维护入口。
- 不重写现有 8-key 面板 UI 和 Profile 配置协议。
- 不把 AC Power Switch 拆成完全独立的一套数据模型和同步流程。
- 不处理 `user-temp/`。

## 推荐方案

采用“现有 8-key Power Switch 体系 + 设备族字段”的方案。

继续使用 `PJEightKeySwitchData` 承载 AC 与 Battery 的共同能力，新增持久化设备族字段，例如 `powerSwitchKind`，区分 `battery` 与 `ac`。旧数据默认迁移为 `battery`。从 AC 入口创建的虚拟开关立即保存为 `ac`，未绑定真实节点时也能限制后续只能绑定 AC PID。

节点识别拆成三层：

- `isBatteryPowerSwitch`：CID `0x0A78` + PID `0x2A01` / `0x2A02`。
- `isACPowerSwitch`：CID `0x0A78` + PID `0x2A11` / `0x2A12`。
- 共同判断，例如 `isPowerSwitch` 或 `isEightKeyPowerSwitch`：Battery 与 AC 都返回 true，用于复用 Profile、配置、订阅、恢复等共同行为。

Panel 类型映射：

- `0x2A01`、`0x2A11`：default scene profile，映射 `.scene8Key`。
- `0x2A02`、`0x2A12`：default brightness profile，映射 `.brightness8Key`。

## 数据与资源

`PJEightKeySwitchRepository` 需要增加设备族字段并做兼容迁移：

- 新表字段缺失时添加，默认值为 Battery。
- 读取 metadata 时，如果记录缺少 kind，默认 Battery。
- 如果旧缓存绑定了真实 AC 节点但 metadata 未保存 kind，可通过节点 PID 修正为 AC，避免误判。

`devices_config.json` 需要增加两条 AC Power Switch 记录：

- `0x2A11`：AC 4SC，默认 scene profile。
- `0x2A12`：AC 4DIM，默认 brightness profile。
- `deviceCategory` 归入 Switches 体系。
- `iconCategory` 使用 `ACPowerSwitch`，匹配已添加资源 `device_ACPowerSwitch`。

如果离线或待同步 AC 图标资源暂未提供，应优先使用现有 fallback，避免本需求扩大到资源补齐。

## 添加与绑定流程

`PJSwitchesTypesVC` 增加第三个选项 `AC Power Switch`，点击后进入现有 `PJPreAddEightKeySwitchesVC`。

`PJPreAddEightKeySwitchesViewModel.CreationKind` 扩展为 AC 类型：

- Battery 入口创建 `powerSwitchKind = battery`。
- AC 入口创建 `powerSwitchKind = ac`。
- 两者都使用 `PJEightKeySwitchData`，共用面板、组、场景、更多设置和持久化逻辑。

绑定真实设备时按设备族过滤：

- Battery 虚拟开关只允许绑定 `0x2A01` / `0x2A02`。
- AC 虚拟开关只允许绑定 `0x2A11` / `0x2A12`。
- 类型不匹配时，扫描列表禁选或绑定准备阶段返回类型不匹配错误。

普通配网流程中，扫描到 Battery 或 AC 真实节点后都创建对应的 `PJEightKeySwitchData`，设备族由 PID 推导。默认配置消息继续复用现有 key config、TX Enable、LED Indicator 逻辑。

AC 添加成功后的收尾行为：

- 不创建初始电量读取请求。
- 不发送 `GenericBatteryGet`。
- 不调用 Battery 版主动断开 Proxy 的逻辑。
- 允许 AC 继续作为当前 Proxy Node。

Battery 添加成功后的收尾行为保持不变。

## 恢复与替换

恢复/替换必须纳入范围。`DeviceRestoreViewController` 使用共同 Power Switch 判断进入 8-key 恢复配置流程，再根据旧虚拟开关 kind 与新节点 PID 做匹配校验。

恢复配置继续复用：

- link group 检查。
- key config、TX Enable、LED Indicator。
- 目标组订阅恢复。
- syncState 与 desired/applied hash 更新。

恢复成功后按设备族收尾：

- Battery：读取电量并主动断开 Proxy，保持现有行为。
- AC：不读取电量、不主动断开 Proxy。

## 同步与激活等待

同步任务继续复用现有 `SyncDevicesViewController(type: .batteryPowerSwitch(...))` 入口或后续中性命名入口。实现时应优先用设备族分支控制行为，避免大范围重命名造成额外风险。

Battery 保持现有低功耗行为：

- SAVE 前或自有配置同步前展示激活等待。
- 启用/禁用时通过激活探测流程发送 TX Enable。
- key config 前后保留现有延时。

AC 分支行为：

- SAVE 需要同步时直接进入同步控制器。
- 启用/禁用直接发送 TX Enable 或进入同步流程，不展示激活等待。
- Key Config、LED Indicator、TX Enable 不做激活探测。
- 跳过 Battery 专用 key config 初始延时和后置等待。
- 目标组订阅/退订完全复用现有逻辑。

## 监控页 UI

继续使用 `PJEightKeySwitchMonitorVC`，但 Header 增加呈现模式：

- Battery 模式：保留电池图标、电量、状态、更新时间和刷新按钮。
- AC 已绑定模式：隐藏电池图标、电量、更新时间和刷新按钮，顶部居中显示 `Online` 或 `Offline`。
- AC 未绑定虚拟模式：顶部显示 `Unlinked`，沿用现有未绑定语义。

在线状态来源使用绑定真实节点的现有在线状态，不引入新的心跳、探测或电量查询。

底部启用/禁用：

- 未绑定虚拟 AC：只更新本地状态并持久化。
- 已绑定 AC：不展示激活等待，直接发起 TX Enable 更新或同步。
- Battery：保持现有激活等待流程。

## 异常处理

- 类型不匹配：禁止或拒绝绑定，并给出类型不匹配提示。
- switch 数量超限：AC 与现有开关共用 16 个上限，沿用 `switchs_overrun_message`。
- 虚拟组地址不足：沿用 `group_address_insufficient_message`。
- 配置失败：AC 复用现有 syncState、desired/applied hash、lastSyncFailedReason 机制，并在列表和监控页显示 sync issue。
- 资源缺失：AC 图标优先使用 `device_ACPowerSwitch`，离线/待同步资源缺失时使用 fallback，避免崩溃或空图。

## 影响文件范围

预计涉及：

- `SunSmart/devices_config.json`
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- `SunSmart/Main/Device/Switches/Model/DeviceSwitchData.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Repositories/PJEightKeySwitchRepository.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJSwitchesTypesViewModel.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJSwitchesTypesVC.swift`
- `SunSmart/Main/Device/Controller/DevicesViewController.swift`
- `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
- `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
- `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJPreAddEightKeySwitchesViewModel.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorHeaderView.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
- `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
- 本地化文件：至少补充 `AC Power Switch` 相关文案。

实现时应保持改动聚焦，不做无关重命名；如果发现某些 Battery 命名必须改为中性命名，应只改受影响边界。

## 验证计划

基础验证：

- Battery PID `0x2A01` / `0x2A02` 仍识别为 Battery。
- AC PID `0x2A11` / `0x2A12` 识别为 AC。
- Battery 与 AC 都能通过共同 Power Switch 判断进入 8-key Profile 能力。
- AC 虚拟开关可创建、持久化、重新加载后仍为 AC。
- AC 虚拟开关只能绑定 AC PID。
- Battery 虚拟开关只能绑定 Battery PID。

流程验证：

- Switches 弹窗展示 `AC Power Switch`，点击进入创建流程。
- AC 添加成功后不会读取电量，不会主动断开 Proxy。
- AC 恢复/替换成功后不会读取电量，不会主动断开 Proxy。
- AC SAVE、启用/禁用不出现激活等待弹窗。
- Battery 原有 SAVE、启用/禁用、初始电量读取和断开 Proxy 行为不变。

UI 验证：

- 未绑定虚拟 AC 顶部显示 `Unlinked`。
- 已绑定在线 AC 顶部居中显示 `Online`。
- 已绑定离线 AC 顶部居中显示 `Offline`。
- Battery 监控页仍显示电池控件、更新时间和刷新按钮。

构建验证：

- 优先执行 SunSmart 真机通用构建：
  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- 如果 implementation 修改到资源、target 配置或共享依赖，需要同步检查 `Archipelago`、`SLG Sync Plus`、`SylSmart` 的影响。

## 分步实施建议

1. 增加 AC PID 识别、共同 Power Switch 判断、devices config 和本地化。
2. 给 `PJEightKeySwitchData` / repository 增加设备族持久化和兼容迁移。
3. 增加 Switches 弹窗 AC 入口，创建 AC 虚拟开关并限制绑定 PID。
4. 调整配网添加和恢复/替换流程，按设备族跳过 AC 电量读取与主动断开 Proxy。
5. 调整 SAVE、启用/禁用和同步控制器中的激活等待分支。
6. 调整监控页 Header 为 Battery/AC 两种呈现模式。
7. 运行构建验证，并针对 Battery 旧行为做回归检查。
