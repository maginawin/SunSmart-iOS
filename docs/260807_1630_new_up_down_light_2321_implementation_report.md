# PID 0x2321 CCT Up&Down Lighting 实施报告

## 结论

已按确认的方案 A 完成本地 App 与 NordicSigMeshSDK 改动。新设备 `CID 0x0A78 / PID 0x2321` 保持独立设备身份，并复用旧设备 `CID 0x0A78 / PID 0x2491` 的设备控制、Lights 图标与行为、Device Parameter Settings、Content Display 继承和 Group Ratio 能力链路。

本报告中的“完成”仅指本地源码、契约检查和 generic iPhoneOS 构建；服务端配置、真实 BLE/Mesh、设备响应和 Group 组播尚未验收。

## App 实施内容

- 在包内 `devices_config.json` 增加用户提供的完整设备配置，保持 `elementCount = 3`、`iconCategory = BidirectionalController`、`deviceCategory = Lighting` 和型号信息不变。
- 在 `Node+Capability.swift` 集中定义 Sunricher 产品能力策略：
  - `0x2321` 与 `0x2491` 均支持 Up/Down Ratio。
  - `0x2321`、`0x2491`、`0x2492` 均支持 Up/Down Light Default CCT Steps。
  - 在原有外部光感灯具名单中增加 `0x2321`。
  - 在原有 Motion Sensitivity 不支持名单中增加 `0x2321`。
  - 所有能力仍要求 Company ID 为 `0x0A78`，避免其他厂商相同 PID 被误判。
- `MeshNetwork+SunSmart.swift` 改为消费同一产品能力策略，移除两组重复的 PID 名单，其他 Emergency、WiFi Gateway 等判断未修改。
- 设备页、Lights 页、参数页和 Group 页继续使用现有能力入口，因此不复制页面、不新增资源和文案。
- Content Display 仍按 Space 设置和现有设备/Group 页面链路生效，不增加 PID 专属配置。

## NordicSigMeshSDK 实施内容

- 新增纯产品策略，集中管理：
  - Default CCT Steps 产品：`0x2321`、`0x2491`、`0x2492`。
  - Up/Down Ratio 产品：`0x2321`、`0x2491`。
- `Node+Propertys.swift` 通过该策略决定 CCT steps 默认值、有效范围和既有持久化资格；未修改 5/6 steps 规则、范围常量、Vendor status 解析或数据库 schema。
- `Node+SupportModels.swift` 通过该策略决定 Group Vendor Model subscription 资格，同时继续要求节点实际存在 Sunricher Vendor Model；未修改 opcode、payload、Model ID、Group Address 或消息生成逻辑。
- 补充 `0x2321` 的 CCT 默认值/范围/status 缓存 XCTest，以及 Group subscription/去重/缺少 Vendor Model XCTest。

## 自动化与构建结果

- App 产品支持契约：通过，输出 `UpDownLightProductSupportContractTests passed`。
- SDK 产品策略契约：通过，输出 `UpDownLightProductPolicyTests passed`。
- `devices_config.json`：`jq empty` 通过。
- SDK 相关 XCTest：使用 iPhoneOS SDK 静态类型检查通过。
- NordicSigMeshSDK generic iPhoneOS `build-for-testing`：通过，输出 `TEST BUILD SUCCEEDED`；该 scheme 的 target graph 只包含生产 Package，因此此结果不等同于 XCTest 已运行。
- SunSmart generic iPhoneOS build：通过。
- Archipelago generic iPhoneOS build：通过；存在原工程的 Info.plist Copy Bundle Resources warning。
- SLG Sync Plus generic iPhoneOS build：通过；存在原工程的重复 FSCalendar source warning。
- SylSmart generic iPhoneOS build：通过；存在原工程的 Info.plist resource 和重复 FSCalendar source warning。
- App 与 SDK 仓库 `git diff --check`：通过。
- App/SDK 生产源码中的 `0x2491` 和 `0x2321` 已分别收敛到各自产品策略，未发现遗漏的同功能独立分支。
- 共享 BidirectionalController 正常、离线、待同步图片资源均已存在；四个 target 均引用 `devices_config.json` 和本地 NordicSigMeshSDK。

## 测试限制

- SDK 的 `swift test` 无法进入 XCTest：SwiftPM 使用 macOS host 编译，而现有生产源码导入 UIKit，报 `no such module 'UIKit'`。这是当前 Package 测试宿主限制，不是本需求断言失败。
- 当前没有可运行的 iOS 真机 test destination，因此新增 XCTest 只完成 iPhoneOS 静态类型检查，尚未实际执行断言。

## 发布前待验收

- 服务端 `/devicesConfig` 在目标区域返回且仅返回一条完整的 `0x0A78 / 0x2321` 配置，并验证新安装、旧缓存升级和重启后的识别路径。
- Classic、Professional、Restore/Reset 添加路径；确认实际 Composition、3 Elements 和 Sunricher Vendor Model。
- 设备分别返回 5/6 CCT steps 时的原始响应、默认/有效范围、保存与重启恢复。
- 单灯页 Ratio GET/SET、失败回滚、亮度/CCT/Ratio 顶部视觉，以及参数页切换、范围、Reset、clamp。
- Lights 页双向灯正常、离线、待同步图标与行为。
- Space Content Display 的 Device Name、CCT Quick Buttons、Simple/Detailed 在单灯页和 Group 页的继承。
- 加入 Group 时 Vendor Model subscription status、Group Ratio button、Group Address SET、混合 Group 行为和 CCT 范围合并。
- 外部光感 Calibration/Profile、Motion Sensitivity 隐藏，以及 `0x2491`、`0x2492` 和普通灯回归。

## Git 状态

本次未执行 commit、push、merge 或 SDK 发布。App 与 SDK 改动分别保留在当前两个工作区中。
