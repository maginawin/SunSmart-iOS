# HDB Lighting Configuration 命令描述方案

日期：2026-10-22。状态：用户确认后已完成 App 实施，未提交。单目标规则与严格新格式、不迁移策略均已落地；真机与外部联调待人工验收。

## 1. 需求结论与最新决定

在 `spaceData.hdb.devices[].lightingConfiguration` 中描述页面 Set 的目标、Property 和控制选项。每条命令只选一个目标，因此采用用户原始结构，不增加 models 数组：

- lightingControl 保留 status/value；mapValues 的 Auto、Force_On、Force_Off 各为一个 elementAddress/modelId/value 对象。
- 五个 LC Property 字段保留 status/value，增加单个 elementAddress/modelId/property。
- failsafeDelay、installDate 继续只有 status/value，不发送命令。
- 不迁移旧格式，保留 schemaVersion=1；缺少新契约字段的旧 HDB 数据不自动补齐或升级，项目重新创建。该策略已由用户确认，不再作为待确认项。
- 业务值仍是百分比或秒，不另存 rawValue。默认值保持 Dim=20%、Bright=80%、Ramp Up=1 秒、Ramp Down=2 秒、Hold=30 秒、Failsafe=5；原示例 Dim=5、Hold=10 是合法配置值。

这里描述设备级配置，没有新增 Site/Space 级独立的 hdb.lightingConfiguration。

## 2. Group Profile 当前实现核对

已沿实际发送链核对：Group Profile 生成 ProfileType → ProfileType.getMessageHandles(node:) → MeshMessageHandle 指定 Model。

- Mode、Occupancy Mode 使用 node.lightLCModel。
- 亮度、Fade On、Fade、Run On 等 LC Property 使用 node.lightLCSetupModel。
- SDK 的 lightLCModel、lightLCSetupModel、lightnessModel 均调用 getFunctionModel；该方法遍历 node.elements，遇到第一个包含对应 SIG Model 的 Element 即返回，不遍历发送其他实例。
- 因此 Group Profile 的上述 LC 参数确实只写一个实例。
- 精确区别：SDK 分别寻找“第一个 LC”和“第一个 LC Setup”，并不在代码中强制它们位于同一 Element。修改前 HDB Lighting Configuration 对 Auto、On、Property 遍历全部匹配实例；本次已将实际目标选择与 JSON 描述一并改为单目标。

依据：

- [App Profile 消息生成](../SunSmart/Common/Data/Node+MessageHandles.swift)
- [Group Profile 差异与任务生成](../SunSmart/Common/Data/Node+SyncData.swift)
- [SDK Model 选择](/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev/Sources/NordicSigMeshSDK/MeshLib/Node/Node+SupportModels.swift)
- [当前 HDB 目标策略](../SunSmart/Common/Data/HDBLightingConfigurationPolicy.swift)

以上结论来自当前源码，不代表多通道设备的实际联动效果已验证。

## 3. 本次单目标执行契约

“第一个”固定为 Composition Element index 最小的匹配项，即有效设备中地址最小的匹配 Element；包括 Primary，不能受外部 JSON 数组顺序影响。SDK 当前实现直接遍历 elements，正常 Composition 顺序与此一致；不依赖异常乱序输入选择目标。

| 字段/选项 | 目标 Element | Model（十进制 / 十六进制） | 命令与参数 |
| --- | --- | --- | --- |
| lightingControl / Auto | 第一个包含 SIG LC Server 的 Element | 4879 / 0x130F | LightLCLightOnOffSet(true) |
| lightingControl / Force_On | 第一个包含 SIG Lightness Server 的 Element | 4864 / 0x1300 | LightLightnessSet(65535) |
| lightingControl / Force_Off | Primary Element | 4096 / 0x1000 | GenericOnOffSet(false) |
| rampDownTime | 上述第一个 LC 所在 Element 的 LC Setup | 4880 / 0x1310 | LightLCPropertySet，property=54 / 0x0036 |
| brightIntensity | 同上 | 4880 / 0x1310 | LightLCPropertySet，property=46 / 0x002E |
| dimIntensity | 同上 | 4880 / 0x1310 | LightLCPropertySet，property=47 / 0x002F |
| holdTime | 同上 | 4880 / 0x1310 | LightLCPropertySet，property=60 / 0x003C |
| rampUpTime | 同上 | 4880 / 0x1310 | LightLCPropertySet，property=55 / 0x0037 |

- 全部是单播、有 ACK，目的地址就是该字段/选项的 elementAddress。LC、Lightness、OnOff 的 elementAddress 不必相同，不使用 Zone groupAddress。
- 第一个 LC 所在 Element 缺少 0x1310 时，该 Property Set 报错且不发送；不改选第二个 LC，也不改选其他 Element 的 LC Setup。
- Auto 明确为 Light LC Light OnOff Set，不是 Light LC Mode Set。三个控制命令省略 Transition Time/Delay，TID 由发送层维护。
- mapValues 同时描述三个选项，但 Set 只选择 lightingControl.value 对应的一项，不遍历发送三个选项。
- Intensity Set 保持 Dim→Bright，Soft Dimming 保持 Ramp Up→Ramp Down。JSON 字段顺序不定义执行顺序。

值的约定：

- brightIntensity/dimIntensity.value 保留百分比，沿用 `UInt32(Double(value) / 100 * 65535)` 向零截断，再编码为 2 字节 Perceived Lightness；80→52428，5→3276。
- rampUpTime/rampDownTime/holdTime.value 保留秒，发送 value×1000，以 3 字节 Time Millisecond 24 编码；2→2000，10→10000。
- mapValues.Auto.value=true、Force_Off.value=false 为 Boolean；Force_On.value=65535 为整数，不使用字符串或混用 Boolean 与数字。

编号和消息语义已交叉核对 [SIG Assigned Numbers](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Assigned_Numbers/out/en/index-en.html)、[Device Properties](https://btprodspecificationrefs.blob.core.windows.net/device-properties/Device_Properties.pdf) 以及 [Mesh Model 1.1](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MMDL_v1.1/out/en/index-en.html)。仅首个实例的选择是本次 App 业务约定，不是标准要求其他实例自动同步。

## 4. JSON 示例

设备 Primary=1234，首个 Lightness 在 1234，首个 LC 及同 Element 的 LC Setup 在 1235。即使后续 Elements 还有同类 Model，也只描述以下目标。

```json
{
  "lightingConfiguration": {
    "lightingControl": {
      "status": "synced",
      "value": "Auto",
      "mapValues": {
        "Auto": { "elementAddress": 1235, "modelId": 4879, "value": true },
        "Force_On": { "elementAddress": 1234, "modelId": 4864, "value": 65535 },
        "Force_Off": { "elementAddress": 1234, "modelId": 4096, "value": false }
      }
    },
    "rampDownTime": {
      "status": "synced", "value": 2,
      "elementAddress": 1235, "modelId": 4880, "property": 54
    },
    "brightIntensity": {
      "status": "synced", "value": 80,
      "elementAddress": 1235, "modelId": 4880, "property": 46
    },
    "dimIntensity": {
      "status": "synced", "value": 5,
      "elementAddress": 1235, "modelId": 4880, "property": 47
    },
    "holdTime": {
      "status": "synced", "value": 10,
      "elementAddress": 1235, "modelId": 4880, "property": 60
    },
    "failsafeDelay": { "status": "synced", "value": 5 },
    "rampUpTime": {
      "status": "synced", "value": 1,
      "elementAddress": 1235, "modelId": 4880, "property": 55
    }
  }
}
```

installDate 未设置时不创建，设置后仍为 status/value，例如 value="22-10-2026"。上述是设备片段，不是完整 Space 导入包。

## 5. 实现方案与影响范围

### 5.1 单一目标选择规则

在 HDBConfiguration.swift 的 HDBLightingWrite.target 中收敛为一个共享选择入口，HDBLightingConfigurationPolicy 调用该入口，供描述生成、页面 Set/Get、初始化中的 Lighting Configuration 参数以及普通参数恢复使用：

- Auto 选首个 LC；Property 使用该 LC 同 Element 的 Setup；On 选首个 Lightness；Off 保持 Primary OnOff。
- 模型来源复用设备 Composition/zoneModels；现有 zoneModels 已覆盖需要的 SIG 类型，Vendor 不参与本次选择。保留 zoneModels、sensorGroupModels、broadcastModels 的现有完整清单和用途。
- 同步调整 Get 的 LC、Lightness、Property 目标，只读取与本次配置对应的实例，避免其他未配置实例造成无关 mixed 结果。
- 页面和普通任务必须使用同一规则，防止页面只设第一实例、后续同步又写全部实例。
- HDB 固定 Preparation（Vendor 参数、LC Mode、Occupancy Mode、Prolong）仍按原有所有实例规则执行；此次用户要求针对 Lighting Configuration 字段，不扩大到这些初始化命令或订阅任务。
- 初始化流程中复用 Lighting Configuration 的五个参数及最后 Auto 会随共享入口收敛为单目标；其中 lightingControl 完成状态仍需满足原有初始化 Mode ACK 与 Auto ACK 条件，不能漏掉初始化屏障。

### 5.2 编解码、数据连续性和严格校验

- 在 HDBConfiguration.swift 的设备上下文编解码中派生命令描述，复用上述策略的常量及目标；不在内存另维护可独立修改的命令清单。
- SQLite hdb JSON、Space 导入/导出/分享/上传及 canonical 统一走同一编解码。解码必须先校验完整描述，再保留业务值/status；不能忽略错误或缺失描述后自动再生，让云端错误回读通过。
- lightingConfiguration=null、未设置的业务字段保持现有合法语义，不凭空创建值。字段存在时，相应的 modelId/property/mapValues 等描述必须完整；mapValues 必须恰好包含三个已知选项。
- 对尚无匹配目标的配置，elementAddress 显式为 null，表示不可下发；该键仍必填。正常可配置设备必须解析为有效单播整数地址。若目标本应存在却写 null，或地址不是本规则选中的首个目标，拒绝该输入。这样保留无模型/空配置的存储能力，不伪造地址，不把旧格式缺字段当作合法 null。
- 缺少首个 LC、同 Element Setup、首个 Lightness 或 Primary OnOff 时，相应 Set 在发包前报错；不因合法保存了 null 目标就把无命令当作成功。failsafeDelay/installDate 不需要这些目标，仍可离线保存。
- 地址、modelId、property 使用 JSON 数字，Boolean 控制值保持 Boolean；完整 Space 导入/导出对照 Composition、设备身份和 zoneModels 验证。failsafeDelay/installDate 不输出也不接受已知命令描述字段。
- 保留现有设备创建、restoreDevice/copyModels、merge/mark、数据库失败与导入回滚机制。设备地址/Composition 改变后，描述从最新保存的设备数据重新生成；导出只读取和校验快照，不修改数据库。
- 当前值、目标、身份或任务版本改变时旧回执不得确认新状态。保存 pending 成功后发送，当前实际目标 ACK 后更新字段；失败、取消、保存失败保持 pending，普通重连不自动重放 Force_On/Force_Off。

严格新格式不迁移已确认。旧 App 重新保存时可能丢弃新字段，不能承诺新旧客户端混写兼容。Web/网关/服务器需完整保存和回读新字段；配套由对应团队实施，本任务只修改 App 与接口文档。

### 5.3 改动位置

1. HDBConfiguration.swift、HDBLightingConfigurationPolicy.swift：单目标描述类型/编解码与共享选择。
2. HDBLightingConfigurationService.swift：Set 复用单目标，Get 对齐；HDBDeviceSyncService.swift：检查初始化和参数恢复的共享调用与完成条件。
3. HDBLightingZonePolicy.swift：按需接入校验/canonical。核对 Database、ImportData、ExportData、SpaceConfigurationIntegrityPolicy 的现有调用，不只在导出层拼字段。
4. 更新既有行为夹具、`docs/261021_1806_HDB_unicast_example.json`、HDB 数据契约与命令文档；持续更新本方案。

实施未涉及 UI 文案、资源、数据库表结构和 SDK API 变化。五品牌共享逻辑以 SunSmart 为代表构建；未修改普通 Group Profile 或 Zone 页组播行为。现有 HDBLightingZonePolicy、Database、ImportData、ExportData 的设备编解码调用已覆盖本次契约，无需另行改动。

## 6. 验证与交付边界

- 多实例与乱序列表只选同一个首目标；LC、Lightness 位于不同 Elements；Primary Off；首个 LC 缺 Setup 但后续有 Setup 时不得 fallback；Vendor 相同低位 ID 不参与匹配。
- 三个 mapValues 和五个 Property 精确匹配；单地址输出；合法 null、缺省字段；缺字段拒绝、不迁移；Boolean/整数、越界、错误目标、错误映射及云端丢字段拒绝。
- JSON 往返、持久化重载、设备恢复/地址改变、merge/mark、导入回滚与 canonical；正常导出只读。
- JSON 目标与页面 Set、Get、初始化中的参数/Auto、普通恢复一致；实际命令数量、值换算与目标正确；固定 Preparation 和三类订阅清单保持原范围。
- 失败/取消/重试/迟到回执/保存失败；Failsafe/Install Date 离线保存不修改其他 pending；初始化 Mode ACK 屏障保留。
- 优先扩展现有 lighting_configuration、configuration、lighting_configuration_service、lighting_messages、persistence、import_recovery 和 device_preparation 相关回归。SDK Property 字节现有部分夹具为替身，涉及实际编码验证时补用生产 SDK 编码，不能用替身替代协议证明。
- Swift 实施完成后一次 SunSmartLocal.xcworkspace / SunSmart / Debug / generic iOS / CODE_SIGNING_ALLOWED=NO 构建，不使用 Simulator、不自动操作真机。

人工验收：多 Element 灯导出单目标；逐项 Set/Get 确认只访问规定首目标；失败重试及重启后状态、描述保持；网关/Web/服务器核对完整字段往返。源码与构建不证明多通道硬件按预期联动。

## 7. 实施与验证结果

已完成：

- 设备上下文编码生成三个 mapValues 和五个 Property 描述；解码先严格核对地址、Model、Property 与值类型，再进入保存、导入或 canonical 比较。无目标用显式 null，旧格式缺字段拒绝，不迁移。
- 页面 Set/Get、初始化五参数和最后 Auto、普通参数恢复共享首目标规则；固定 Preparation 与订阅范围保持不变。
- 同步任务捕获模型快照，同时检查当前 Composition 与已保存模型。新增回归先复现“Composition 已变化但旧目标 ACK 仍写入 synced”，修复后旧回执被拒绝，字段保持 pending。
- 更新完整 JSON 示例、Site 命令文档和设备模型清单契约。

自动验证：

- `check_hdb_configuration.py`：新旧格式边界、三个映射与五属性、错误元数据拒绝、显式 null 目标、null 业务字段往返及现有文档样本通过。
- `check_hdb_lighting_configuration.py`：多实例与乱序首目标、首 LC 缺 Setup 不 fallback、百分比截断与秒到毫秒换算、字段状态与往返通过。
- `check_hdb_lighting_configuration_service.py`：页面 Set/Get 单目标、独立字段 ACK、失败/重试/取消及迟到回执通过。
- `check_hdb_persistence.py`、`check_hdb_import_recovery.py`：持久化与导入边界、保存失败/回滚、云端回读丢字段必须拒绝通过；这些使用隔离边界，不等同本机账户数据库或真实服务器验收。
- `check_hdb_lighting_messages.py`：Auto 生产构造入口、Preparation 参数与 Vendor ACK 检查通过；Property 字节编码部分仍使用测试替身，不据此宣称完整真实协议字节已验证。
- `check_hdb_integration.py` 默认模式和 `--device-sync`、`--device-tasks`：设备恢复后描述地址更新、共享订阅、空目标、初始化字段重试、旧目标 ACK 拒绝和普通恢复不重放 Force 通过。多 LC 用例直接确认固定 Mode 覆盖两个 LC、五参数/Auto 仅首 LC，缺少第二个 Mode ACK 时 lightingControl 保持 pending，重试成功后才 synced。
- `check_hdb_device_preparation.py` 的 Preparation 与 device-sync 阶段通过。首次运行在新多 LC 夹具失败：夹具遗漏第二个 LC 必需的 FEFD 订阅，真实 SDK readiness 拦截任务；补齐夹具前置条件后 device-tasks 通过，未放宽生产检查。
- 聚合脚本余下的 `--add-completion`、`--add-execution`、`--subelement` 已分别运行通过，覆盖加设备完成屏障、初始化/上传状态、订阅恢复、失败/取消和迟到回执；所有聚合阶段均已有通过结果。
- `git diff --check` 通过。

SunSmartLocal.xcworkspace / SunSmart / Debug 通用 iOS 构建通过（退出码 0）：

```sh
xcodebuild -workspace SunSmartLocal.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath /Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-HDB-261020 CODE_SIGNING_ALLOWED=NO build -quiet
```

构建仍有其他文件的编译警告。构建后只补充测试与文档，没有再修改生产代码。数据契约和发送生命周期分别完成独立只读审查，均未发现可确认缺陷；审查建议的 null 字段、恢复地址和多 LC Mode ACK 组合路径已补充回归。

未执行真机、网关、Web 或服务器联调，未重新执行真实 SQLite 集成；数值换算和隔离协议检查不证明多通道硬件的实际联动。外部执行方需完整保存、回读新字段；旧客户端重新保存可能丢字段，严格新格式客户端会拒绝这些数据。

最短人工验收：

1. 新建 HDB 项目并加入多 Element 灯，导出核对首 LC、同 Element Setup、首 Lightness 与 Primary Off 地址。
2. 逐项 Set/Get，核对实际访问目标；中断一次参数下发后重试，重启后确认值、pending/synced 和描述一致。
3. 网关/Web/服务器完成完整字段往返，特别确认 mapValues 与各 Property 描述不被丢弃；旧格式导入应拒绝。

## 8. 当前交接状态

App 分支 feat/HDB-261020，HEAD=0795438a；4 个生产 Swift 文件及相关测试、样例、文档已修改，未 commit/push。工作期间 protocols/HDB 下另出现数值换算文档，未由本任务修改。SDK 映射指向 one-dev，HEAD=8c5af55，保留既有未提交差异，未修改 SDK。

App 代码与自动验证已完成；外部字段往返、多 Element 实际发包与硬件联动待上述人工验收。不迁移旧格式已确认，后续无需重复确认该项。
