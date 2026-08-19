# Light Information Date time / Time zone 实现总结

## 1. 实现结果

已按 2026-08-20 确认的需求完成实现：仅从 `Site -> Main -> Lights` 的灯详情进入 Information 时，对 Composition Data 中包含 Time Server Model 的设备，在 `Signal strength` 后展示 `Date time` 和 `Time zone`。

本次实现保持以下边界：

- 2026-08-20 更新：不支持 TimeGet 的灯仍展示两行，右侧均显示本地化的 `Not supported`，且不发送配置或读取消息；
- Mesh 未连接时两行显示 `--` 并展示离线 Toast；
- 页面进入后不监听 Mesh 连接变化，也不自动重试；用户点击任一时间行时才重试；
- 本地 Provisioner 的 Time Client Binding 会进行幂等修复；
- 远端 Time Server Binding 仅在用户具有设备编辑权限时自动修复；
- Binding 成功但 TimeGet 失败时保留 Binding，不回滚远端配置；
- 不发送 TimeSet，不修改 Site timezone，不新增普通灯云同步；
- Gateway Information 现有 direct Proxy、读取、持久化和云同步行为保持不变。

## 2. 主要改动

### App

- 新增 `LightTimeInformationCoordinator`，负责连接检查、权限决策、远端 Binding、TimeGet、有效响应校验、本地 Node 保存与失败回滚。
- `DeviceLightViewController` 是唯一注入 Light Time Context 的入口，编辑权限来自 `space.deviceOperates.contains(.edit)`。
- `DeviceInformationViewController` 在 Light Context 存在时追加时间行；缺少真实 `node.timeModel` 时展示 `Not supported`，支持时处理进入读取、点击重试、Toast 和页面退出隔离。
- 新文件已加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 target。
- 标题和 Toast 均复用现有英中本地化 Key，没有新增或硬编码用户文案。

### NordicSigMeshSDK

- 将 Time Client `0x1202` 纳入本地 Client Model 自动 Binding 白名单。
- 新增 `ensureLocalTimeClientModelBinding()`，针对当前 AppKey 幂等检查和修复本地 Time Client Binding，并保存 local Node。

### 测试与检查

- 新增 Light 时间准备策略测试，覆盖：不支持、缺 AppKey、本地 Client 不可用、已配置只读、编辑者补 Binding、只读禁止远端配置。
- 新增运行时源码合同，固定入口范围、权限来源、远端状态字段校验、TimeGet-only、无云同步、四 target membership 和 SDK API。
- 新增聚焦检查脚本，并串联既有 Gateway 时间回归检查。

## 3. 自动验证结果

以下检查已通过：

- Light Time Information 策略测试；
- Light Time Information 运行时合同；
- Gateway Information / Gateway Clock / Fast Add 时间相关既有回归合同；
- English、简体中文 strings 语法检查；
- Xcode project 文件语法检查；
- `git diff --check`；
- SunSmart generic iPhoneOS Debug build；
- Archipelago generic iPhoneOS Debug build；
- SLG Sync Plus generic iPhoneOS Debug build；
- SylSmart generic iPhoneOS Debug build。

SDK 的主机端 `swift test` 未能执行完成，原因是 SDK 现有源码直接依赖 UIKit，而 macOS SwiftPM 编译环境没有 UIKit；四个 iPhoneOS 构建已实际编译本地 SDK 和新增 App 调用，均成功。

## 4. 仍需真机验收

自动测试和通用 iPhoneOS 构建不能替代真实 Mesh 设备验收，建议至少覆盖：

1. 支持 Time Server、Binding 已正确：进入页面直接读到时间和时区。
2. 支持 Time Server、远端未 Binding、Editor：先成功补 Binding，再读到时间。
3. 支持 Time Server、远端未 Binding、无编辑权限：不修改设备，显示失败提示。
4. 不支持 Time Server：两行均显示 `Not supported`，并确认没有 Binding 或 TimeGet。
5. Mesh 未连接：两行为 `--`、出现离线 Toast；稍后连接不会自动读取，点击后才读取。
6. Binding 成功、TimeGet 超时：下次重试不回滚已完成 Binding。
7. TimeStatus seconds 为零或异常 Offset：不覆盖原 Node 时间快照。
8. 多 Element 灯：TimeGet 和 Binding 均发送到 Time Server 所在的实际 Element。
9. 四品牌 App 的 Information 行位置、英文/中文文案和点击区域视觉验收。

## 5. 工作区说明

本次未执行 commit、push、merge 或清理操作。实现前后均保留工作区内其他未跟踪文档，没有对其进行修改。
