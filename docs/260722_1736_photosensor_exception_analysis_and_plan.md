# Photosensor Exception 需求、协议分析与开发方案（方案 A 已实施）

## 1. 结论

在将 UI 数值范围修正为 `1%...100%` 后，需求与协议主体一致，可以完整实现 Photosensor Exception 的读取、设置、本地持久化、设备列表展示、Filter 筛选和云同步。

推荐采用“强类型状态贯穿 SDK 与 App”的方案：未知状态单独使用 `nil` 表达，协议有效状态使用 `Disabled` 或 `Enabled(maxPercent: 1...100)` 表达；协议返回的 `101...255` 在解析边界立即归一化为 `Disabled`。这样不会把“未读取”和“禁用”混为一谈，也不会让无效原始值进入 UI、数据库或云端。

本需求仍有两个外部确认项，但不阻塞 iOS 侧方案设计：

1. 云端接口需确认接受并原样返回新增字段 `photosensorException`；如果服务端存在字段白名单，仅修改 iOS 无法保证跨设备云同步。
2. GET 失败时的 `ret` 取值和负载长度没有在协议中定义。客户端可以把所有非 `0` 的 `ret` 统一视为读取失败，但建议协议文档补齐。

## 2. 修正后的业务语义

### 2.1 协议值与领域状态

| 原始 U8 | 领域状态 | Device 列表 / Filter 展示 |
| --- | --- | --- |
| 尚未读取或读取失败 | Unknown | `--` |
| `0` | Disabled | `Disabled` |
| `1...100` | Enabled，值为右侧最大百分比 | `0%~N%` |
| `101...255` | Disabled（协议定义的无效值归一化） | `Disabled` |

`15%` 不是功能上限，只是 Figma 中的当前值示例，同时也是启用后的默认值。Slider 的实际范围为 `1...100`，步长为 `1`；左边界 `0%` 固定且不可调，Slider 只调整右边界 `N%`。

### 2.2 三层开关/状态的区分

- 参数卡片右上角开关：表示本次批量设置是否包含 Photosensor Exception。关闭时不发送该参数。
- 卡片内部 `Feature switch`：表示要写入设备的功能状态。关闭时发送 `0`；开启时发送 `1...100`。
- 设备已读取状态：`Unknown / Disabled / Enabled(N)`，用于列表、Filter、本地保存和云同步，不应与“本次是否选择设置该参数”混用。

建议编辑页的初始值为：参数卡片未选择、Feature switch 为 Disabled、预备最大值为 `15`。首次开启 Feature switch 时显示 `15%`；用户调整后在本次编辑会话内切换开关时保留该值，`Reset` 始终恢复到 `15%`。

## 3. Figma 与 UI 实现方案

### 3.1 Device Parameter Settings

仅对 `companyId = 0x0A78` 且 `productId = 0x2057` 的设备：

- 参数顺序调整为 `Rated power`、`Absolute Sensitivity`、`Transition Timer`、`Photosensor Exception`。
- 不再提供 `PWM`。
- Photosensor Exception 参数卡片需要独立 Cell，因为现有 Transition Time Cell 只有“参数是否选中”一个开关，而新卡片同时具有外层参数选择开关和内部 Feature switch。
- 复用 Transition Time 已有的 Reset、Slider、减号、加号、字体、颜色、圆角和间距，不另建一套视觉规范。
- Feature switch 为 Disabled 时：显示 `Disabled`、Note 和 Default 说明；隐藏 Reset 和数值调节区。
- Feature switch 为 Enabled 时：显示 `Enabled`、Reset、Slider、减号、加号、动态值 `N%`、Note 和 Default 说明。
- Slider 最小值 `1`、最大值 `100`、步长 `1`，默认值 `15`；设备范围的语义展示统一格式化为 `0%~N%`。
- 参数卡片外层未选择时沿用现有参数页面的收起逻辑，不参与设置任务。

新增用户可见文案全部进入 English 与简体中文本地化文件。`Reset`、`Default` 等已有且语义完全相同的 Key 优先复用；Photosensor Exception 标题、状态、Note 和 Default 长文新增独立 Key。Figma 中的英文长文建议在实现前由产品最终校对一次，避免代码完成后再改布局。

### 3.2 Device 列表

对支持该功能的设备新增一行：

- 未读取或本次读取失败：`Photosensor Exception: --`
- 禁用：`Photosensor Exception: Disabled`
- 启用：`Photosensor Exception: 0%~N%`

读取失败只把本次展示用临时值置为 Unknown，不应覆盖数据库中最后一次成功读取的正式值。

### 3.3 Filter 弹窗

- Photosensor Exception 位于 Transition Timer 之后，默认收起；如果已有筛选选中值，则沿用当前 Filter 行为自动展开。
- 选项固定按状态优先级生成：`--`、`Disabled`、所有不同的 Enabled 范围。
- `--` 仅在至少一个支持设备为 Unknown 时出现。
- `Disabled` 仅在至少一个支持设备为 Disabled 时出现；协议原始值 `101...255` 已被归一化，因此不会生成额外非法选项。
- Enabled 范围去重后按右侧百分比升序展示，例如 `0%~1%`、`0%~15%`、`0%~100%`；`15%` 不作特殊排序。
- Filter 只统计明确支持此功能的设备；不支持的设备不进入该项的选项来源和匹配结果。

## 4. 协议分析

### 4.1 字节布局

当前 SDK 对厂商 Opcode 的内部写法为字节序整数：

- SET：`0xF0780A`
- GET：`0xF1780A`
- RET：`0xF3780A`

这与协议文档的 `0xF00A78 / 0xF10A78 / 0xF30A78` 是同一组 Vendor Opcode + Company ID 的不同书写方式，不构成冲突。

Photosensor Exception 的 Access Payload 应为：

- SET 请求：`31 40 VV`
- SET 返回：`31 40 RR`
- GET 请求：`31 40`
- GET 成功返回：`31 40 00 VV`

其中 `VV` 为 `0...255`，`RR` 已定义 `00 = success`、`02 = length error`。

### 4.2 编号冲突检查

- 现有 `VendorDaylightSensorCode` 使用 `0x36...0x3F`，因此 `0x40` 是该主类型下紧邻且未占用的新子码。
- SDK 中另有 `VendorOpCode.motionSensitivity = 0x40`，它是主类型值；本功能的 `0x40` 是主类型 `0x31` 下的子码，两者命名空间不同，不冲突。
- SET 与 GET 返回都使用 `31 40`，通过请求上下文和返回长度区分，这是现有消息队列可以承载的模式；同一节点、同一模型不得并发挂起该属性的 GET 与 SET，继续走现有串行读写任务队列。

### 4.3 解析规则

- SET 返回必须严格为 3 字节参数；`ret = 0` 成功，其他值失败并保留错误码。
- GET 成功返回必须严格为 4 字节参数；不足或多余均视为格式错误，不能更新 Node。
- GET 的 `ret != 0` 统一视为读取失败；待协议补齐其错误码和长度定义。
- GET 值 `0` 解析为 Disabled，`1...100` 解析为 Enabled，`101...255` 立即归一化为 Disabled。
- App 只允许发送 `0...100`；永不主动发送 `101...255`。

## 5. 技术方案比较

### 方案 A：强类型状态贯穿 SDK 与 App（推荐）

Node 使用可空的 Photosensor Exception 状态；Unknown 由 `nil` 表达，有值时只能是 Disabled 或合法的 Enabled 百分比。数据库和云端仍使用一个可空 U8 字段存储。

优点是状态边界清楚、非法值只处理一次、UI/Filter 不会重复写判断，后续协议扩展也更安全。改动文件多于直接存数字，但都属于该功能的必要链路。

### 方案 B：全链路直接保存可空 UInt8

`nil / 0 / 1...100` 分别表达 Unknown、Disabled、Enabled，并在各层重复处理 `101...255`。

改动稍少，但 UI、Filter、导入、数据库和消息解析都可能各自遗漏合法性判断，长期维护风险较高。

### 方案 C：仅在 App 内拼装厂商消息

不修改本地 NordicSigMeshSDK，由 App 自行构造和解析原始消息。

改动看似集中，但会绕开 SDK 的响应匹配、Node 更新与持久化体系，也无法复用现有读写管线，不适合本需求。

## 6. 推荐开发拆分

### 阶段 1：NordicSigMeshSDK 协议与状态

1. 在 Daylight Sensor 子码、ResponseCode、SET/GET function、状态参数中加入 Photosensor Exception。
2. 增加严格长度校验、错误码处理和 `101...255 -> Disabled` 归一化。
3. SET 成功时根据请求更新 Node；GET 成功时根据返回更新 Node，并调用现有属性保存入口。
4. 为 Node 增加可空状态、数据库可空列、兼容性迁移、读写映射和 RestoreData 字段。
5. 增加协议编码、解析、响应匹配、Node 更新和数据库往返测试。

### 阶段 2：App 数据管线

1. 增加精确能力判断：必须同时匹配 CID `0x0A78` 与 PID `0x2057`，且存在 Sunricher Vendor Model。
2. 对同一精确设备让 `supportPwmFrequency` 返回 false；不删除其他产品的 PWM 功能，也不清理历史 PWM 数据。
3. 扩展参数类型、读取类型、同步任务、失败映射、重试、恢复同步和成功回调；新增 rawValue 时只追加新值，不重排既有值。
4. 混合选择设备时采用“能力交集”策略：只有全部所选设备均支持 Photosensor Exception 才在设置页出现，避免向不支持设备发送 `31 40`。设备列表读取和 Filter 则始终按单节点能力判断。
5. 在参数设置成功后清理对应 RestoreData 待恢复值，保持与现有参数一致。

### 阶段 3：本地与云持久化

1. 本地数据库使用可空字段：`nil = Unknown`、`0 = Disabled`、`1...100 = Enabled`。
2. 两条现有 Export 路径都导出 `photosensorException`，两条 Import 路径都读取并归一化该字段。
3. 缺失字段保持 `nil`，确保旧云数据和旧本地数据库向后兼容。
4. 云端字段只上传归一化值，不上传 `101...255`。
5. 服务端确认字段不被白名单过滤，并完成“设备 A 上传、设备 B 下载”的真实往返验收。

### 阶段 4：UI 与 Filter

1. 新增 Photosensor Exception 专用参数 Cell，复用现有视觉组件。
2. 接入外层参数选择、内部 Feature switch、Reset、Slider 和动态值。
3. 扩展设备 Cell 的 Unknown/Disabled/Enabled 展示和失败标记。
4. 扩展 Filter 的数据收集、排序、去重、选择状态、重置状态和实际过滤。
5. 补齐 English、简体中文文案，优先复用现有资源图标；若现有日光/传感器图标与 Figma 不匹配，再最小化新增资源并同步检查所有 target。

## 7. 验证计划

### 自动化与静态验证

- SDK 编码：SET `0`、`1`、`15`、`100`；GET 空参数。
- SDK 解码：SET `ret 0/2`；GET 返回 `0`、`1`、`15`、`100`、`101`、`255`；非法长度；错误主码/子码。
- 响应匹配：确认 `31/40` 不会匹配 `31/3F` 或主类型 `40`。
- 状态格式化：Unknown、Disabled、Enabled 边界值。
- Filter：顺序、去重、多设备不同 Enabled 值、Unknown 与 Disabled 并存。
- 能力：仅 `0x0A78/0x2057` 支持，且该设备不再支持 PWM。
- 云数据：缺失、`0`、合法值、`101...255` 的导入导出往返。
- `git diff --check`。
- 直接使用 generic iPhoneOS 分别构建 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart`，不使用 Simulator。

SDK 的 macOS `swift test` 可能受 UIKit 依赖限制；若发生该已知环境限制，应记录为阻塞项，并以 SDK iPhoneOS 工程构建和 App 四个 target 构建补充静态集成验证，但不能把构建成功描述为硬件协议已验收。

### 真机 / Mesh / 云验收

- 首次进入列表显示 `--`，读取后分别正确显示 Disabled 与 `0%~N%`。
- 写入并回读 `0`、`1`、`15`、`100`。
- 固件返回 `101`、`255` 时显示并保存为 Disabled。
- `ret = 2`、超时、短包、长包均显示任务失败且不污染最后成功状态。
- Reset 恢复 `15%`，加减按钮和 Slider 在 `1...100` 边界内工作。
- 多台相同设备配置不同值时，Filter 展示全部去重范围并能准确筛选。
- App 重启、Mesh 重连、设备恢复后状态和待同步行为正确。
- 云上传后由另一客户端重新导入，Unknown/Disabled/Enabled 语义保持一致。

## 8. 已确认的实施基线

如无另行调整，实施将采用以下基线：

1. 采用方案 A（强类型状态）。
2. Slider 范围 `1...100`、步长 `1`、默认/Reset 值 `15`。
3. Filter 的 Enabled 项按右侧百分比升序，不把 `15%` 特殊置顶。
4. `101...255` 在所有导入边界归一化为 Disabled，并持久化/上传为 `0`。
5. 混合选择设备时使用能力交集；只有全部选中设备都支持时才显示该设置项。
6. 云字段暂定为 `photosensorException`，需服务端确认可透传。

## 9. 实施结果（2026-07-22）

已按方案 A 完成以下范围：

1. NordicSigMeshSDK 已加入 Photosensor Exception 的强类型状态、SET/GET/RET 编解码、严格返回长度判断、响应匹配、Node 更新、本地数据库迁移与 RestoreData 支持。
2. 协议原始值按 `0 = Disabled`、`1...100 = Enabled(N)`、`101...255 = Disabled` 归一化；App 主动写入仅产生 `0...100`。
3. App 已按 CID `0x0A78`、PID `0x2057` 和 Vendor Model 做精确能力判断；该设备隐藏 PWM，新增 Photosensor Exception。
4. Device Parameter Settings 已接入外层参数选择、内部 Feature switch、Reset、Slider、减号、加号、动态 `N%`、Note 与 Default；Slider 范围为 `1...100`，默认和 Reset 为 `15`。
5. 设备列表已支持 `--`、`Disabled`、`0%~N%`；Filter 已按 `--`、`Disabled`、Enabled 数值升序生成去重选项。
6. 读取、设置、失败重试、恢复同步、成功回写、本地保存和两条云导入导出路径均已接入。
7. English 与简体中文文案已补齐，现有资源和组件优先复用，没有新增 target 资源配置。

### 已执行验证

- NordicSigMeshSDK iPhoneOS 构建通过。
- App 的 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 scheme 均通过 generic iPhoneOS Debug 构建。
- App 与 SDK 两个仓库的 `git diff --check` 均通过。
- 已新增协议状态、编码、解析、异常值归一化、RestoreData 和 SET/GET 响应形状测试。

SDK 的 `swift test` 仍受现有源码顶层依赖 UIKit 限制，macOS 测试环境报 `no such module 'UIKit'`，因此新增 XCTest 本次没有实际跑通，不能记为测试通过。尝试使用 iPhoneOS SDK 单独类型检查测试文件时，环境又缺少 Swift XCTest overlay，同样无法替代正式测试执行。

### 尚需外部验收

1. 使用目标固件真机验证 SET/GET/RET、超时、`ret = 2`、短包、长包以及原始值 `101/255`。
2. 验证 UI 动态高度、长文布局、Slider 边界和多设备 Filter 的真实交互。
3. 确认云端允许透传 `photosensorException`，并完成两台客户端之间的上传、下载和归一化往返。
