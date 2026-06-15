# Up Down Light Up Ratio Vendor Protocol 设计

## 背景

当前 `up-down-light` 分支已经为 `0x0A78 / 0x2491` 单灯和 group control 规划了 Up/Down Ratio UI。现有实现把 `upRatio` 存在 `Node.PreConfiguration`，只作为本地 UI 状态，不发送 Mesh/vendor 命令，也不参与云同步。

本次目标是为 `NordicSigMeshSDK` 增加 up down light 的私有 Vendor SIG Mesh 协议，使 App 可以通过 SDK 读取和设置设备端真实的 up ratio。

## 已确认协议

Vendor opcode 仍沿用 SDK 现有常量表示：

- SET：`SunricherVendorSet.opCode = 0xF0780A`，对应协议文档 `0xF00A78`。
- GET：`SunricherVendorGet.opCode = 0xF1780A`，对应协议文档 `0xF10A78`。
- RET：`SunricherVendorStatus.opCode = 0xF3780A`，对应协议文档 `0xF30A78`。

新增 payload 层命令：

- 主 opcode：`0x53`，up down light。
- subcode：`0x02`，up ratio。
- up ratio 范围：`0...100`，`down ratio` 不独立传输，始终由 `100 - upRatio` 得到。

SET payload：

- 请求：`[0x53, 0x02, upRatio]`。
- 应答：`[0x53, 0x02, ret]`。
- `ret = 0` 表示成功，`ret = 1` 表示失败。

GET payload：

- 请求：`[0x53, 0x02]`。
- 应答：`[0x53, 0x02, ret, upRatio]`。
- 只有 `ret = 0` 且长度足够时读取 `upRatio`。

## 非目标

- 不修改现有 `SunricherVendorSet/Get/Status` 的 opcode 常量。
- 不为该子功能新建独立 Mesh message 类型。
- 不改变 `0x0A78 / 0x2491` 的能力判断规则。
- 不把 `upRatio` 新增到 share/import、space cloud sync 或 `Node.export()` payload。
- 不在本设计阶段改 UI 或实现命令下发。
- 组内 up ratio set 不逐节点等待 ACK，不做失败判断。

## 方案对比

### 推荐方案：接入现有 Sunricher Vendor 架构

在 SDK 的集中式 Vendor 协议模型中新增 up down light 分支：

- `VendorOpCode.upDownLight = 0x53`。
- `VendorUpDownLightCode.upRatio = 0x02`。
- `ResponseCode.upDownLightUpRatio`。
- `VendorFunctionSet.upDownLightUpRatio(UInt8)`。
- `VendorFunctionGet.upDownLightUpRatio`。
- `FunctionParameters.upDownLightUpRatio(UInt8)`。

优点：

- 符合 SDK 现有私有协议实现方式。
- 复用 `SunricherVendorStatus` 的 `ret` 解析和错误处理。
- 复用 AccessLayer 对同一 RET opcode 的前两字节 function-code 匹配，避免并发 ACK 串包。
- App 调用方可以继续使用类型化的 `SunricherVendorSet/Get`。

缺点：

- `SunricherVendorStatus.swift` 的集中枚举会继续变大。

### 备选方案：新增独立 UpDownLight Message 类型

为该协议新增独立 `UpDownLightVendorSet/Get/Status` 类型。

优点是边界更清晰。缺点是要额外接入 response matching、model delegate、App 调用和测试路径；对一个 `0x53 / 0x02` 子功能来说改动偏重，也不符合当前 SDK 的 Sunricher 私有协议风格。

### 备选方案：App 侧直接发送 raw payload

App 构造 raw vendor payload 并自行解析回包。

优点是短期改动少。缺点是绕开 SDK 类型系统，错误处理、并发响应匹配和后续复用都会分散，不适合作为 SDK 能力。

## 最终设计

采用推荐方案。

SDK 编码规则：

- SET 编码：`SunricherVendorSet(function: .upDownLightUpRatio(value))` 生成 `[0x53, 0x02, value]`。
- GET 编码：`SunricherVendorGet(function: .upDownLightUpRatio)` 生成 `[0x53, 0x02]`。
- `value` 在 SDK 入口 clamp 到 `0...100`，避免 App 传入越界值造成非法 payload。

SDK 解码规则：

- `SunricherVendorStatus(parameters:)` 识别 `0x53 / 0x02` 为 `ResponseCode.upDownLightUpRatio`。
- `ret != 0` 时 `isSuccessful = false`，`errorCode = ret`，`parameters = nil`。
- `ret == 0` 且只有 3 字节时，按 SET ACK 处理，`parameters = nil`。
- `ret == 0` 且长度至少 4 字节时，读取第 4 字节为 `upRatio`，输出 `.upDownLightUpRatio(upRatio)`。
- GET 返回的 `upRatio` 若大于 `100`，视为无效返回：`isSuccessful = false`，`parameters = nil`。

App 后续接入规则：

- 进入目标设备页时，可以发送 GET 获取设备真实 up ratio；成功后更新 `node.upRatio` 和当前 UI，并保存本地 `preConfiguration` 缓存。
- 单设备页 slider 拖动中只更新本地 UI，不连续发送 SET。
- 单设备页 slider 结束或快捷按钮确认时发送 SET；成功后保存本地缓存。
- 单设备页 SET 失败或超时时，必须回滚到最后一次已确认的 `upRatio`，同时刷新 `DeviceUpDownRatioControlView` 和顶部 `UpDownLightView`。
- group control 的 up ratio set 组件复用同一个交互原则：slider 拖动中只更新本地 UI，只有拖动结束或快捷按钮确认时发送命令。
- group control 对含有 up down light 的组使用组播地址发送一次 SET 命令，默认全部成功，不等待每个成员设备 ACK，也不做失败回滚。
- group control 组播发送后，把本地 `upRatio` 写入所有 `supportsUpDownRatioControl` 成员节点并保存本地缓存；不新增 group 级 ratio 模型字段。

## 数据流

读取流程：

1. App 找到目标节点的 vendor model。
2. App 发送 `SunricherVendorGet(function: .upDownLightUpRatio)`。
3. SDK 编码为 `[0x53, 0x02]`。
4. 设备返回 `[0x53, 0x02, 0x00, upRatio]`。
5. SDK 解析为 `.upDownLightUpRatio(upRatio)`。
6. App 更新 `node.upRatio`、刷新 Up/Down Ratio UI、保存本地缓存。

单设备设置流程：

1. 用户停止拖动 slider 或点击快捷按钮。
2. App 发送 `SunricherVendorSet(function: .upDownLightUpRatio(value))`。
3. SDK 编码为 `[0x53, 0x02, value]`。
4. 设备返回 `[0x53, 0x02, ret]`。
5. `ret = 0` 时 App 保存本地缓存。
6. `ret = 1` 或超时时 App 回滚到最后一次已确认的 `upRatio` 并刷新 UI。

组内设置流程：

1. 用户在 group control 的 up ratio set 组件中停止拖动 slider 或点击快捷按钮。
2. App 使用组地址发送 `SunricherVendorSet(function: .upDownLightUpRatio(value))`。
3. SDK 编码为 `[0x53, 0x02, value]`。
4. App 默认组播发送成功，不等待组内成员逐个返回 RET。
5. App 将 `value` 写入组内所有 `supportsUpDownRatioControl` 成员节点的本地 `upRatio` 并保存缓存。

## 错误处理

- SDK 不吞掉 `ret = 1`，必须通过 `SunricherVendorStatus.status.isSuccessful == false` 暴露给调用方。
- 短包、未知 subcode、GET 成功但缺少 up ratio 都不生成有效参数。
- 越界 up ratio 不写入 `FunctionParameters`，避免 App 把非法设备返回当作真实状态。
- AccessLayer 继续使用请求 payload 前两字节 `[0x53, 0x02]` 匹配 RET，避免同源同目标的其它 Sunricher Vendor 请求误匹配。
- 单设备页必须消费 SET 结果：成功才确认本地状态，失败或超时必须回滚。
- group control 使用组播发送，业务上默认成功，不根据 RET 判断失败，也不回滚本地组内成员状态。

## 测试计划

SDK 单元测试：

- SET 编码：`upRatio = 0 / 50 / 100`。
- SET 输入越界 clamp：小于 0 的 App 层值不适用于 `UInt8`，SDK 重点覆盖大于 100 的 `UInt8` clamp。
- GET 编码：`[0x53, 0x02]`。
- SET ACK 解析：`[0x53, 0x02, 0x00]` 成功且无参数。
- SET 失败解析：`[0x53, 0x02, 0x01]` 失败，`errorCode = 1`。
- GET 成功解析：`[0x53, 0x02, 0x00, 0x64]` 得到 `.upDownLightUpRatio(100)`。
- GET 短包和越界返回不产生有效参数。
- response matching 覆盖 `[0x53, 0x02]`，确认不会匹配其它 Sunricher Vendor RET。

App 验证：

- 单设备页拖动 slider 过程中不发送 up ratio SET；只有拖动结束发送一次。
- 单设备页 SET 返回失败或超时时，ratio 控件和顶部灯图回滚到最后一次已确认值。
- group control 拖动 slider 过程中不发送 up ratio SET；只有拖动结束发送一次组播 SET。
- group control 组播后默认成功，更新组内 up down light 成员本地缓存，不做失败回滚。
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`。
- 若改动后涉及其它品牌 target 的共享编译风险，再补 `Archipelago`、`SLG Sync Plus`、`SylSmart` 对应 iPhoneOS build。

## 实施边界

本设计只确认 SDK 协议模型和 App 接入策略。正式实现前需要单独写 implementation plan，按阶段执行：

1. SDK 协议枚举、编码、解码和测试。
2. App 单设备页面 GET/SET 接线和失败处理。
3. App group control up ratio set 组件接入组播 SET 和本地缓存更新。
