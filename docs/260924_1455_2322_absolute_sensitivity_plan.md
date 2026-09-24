# 0x0A78 / 0x2322 灵敏度行为对齐

日期：2026-09-24。生产代码已改为复用现有能力名单；本轮已同步测试与文档，定向回归通过。当前实现尚未重新构建 App，真机待人工验收。

## 最终确认范围

`0x0A78 / 0x2322` 与 `0x0A78 / 0x2132` 保持以下行为一致：

- 在 Site → Space → More → Device Parameter Settings 隐藏 Absolute Sensitivity。
- Group 的 Relative sensitivity 仍按现有权限允许编辑，保留保存、同步和退组还原逻辑。
- Group 中存在任意一台上述两种设备，且当前 Profile 显示灵敏度卡片时，显示 **Some devices lack sensitivity**。
- 全部成员或部分成员属于这些设备时，均使用同一句提示；保留其他型号原有的提示规则。
- 沿用现有提示文案、布局、帮助页和本地化。Daylight / Manual Control 等原本隐藏该卡片的 Profile 保持原行为。
- `0x2322` 加入现有外接光感名单，同时复用相应校准选择流程中的外接传感器连接确认提示。
- `0x2131` 不在外接光感名单中，不因该 PID 触发 Group 的灵敏度提示或外接光感连接提示；它原有的 Absolute Sensitivity 禁用规则保留。

Group 继续使用 **Some devices lack sensitivity**，不区分“全部”或“部分”。本次沿用既有相对灵敏度编辑、任务及恢复机制。

## 工作状态与入口

- App 分支：`fix/BL9105N-XXCCTXXE-260924`；实施基线 HEAD：`d32d16d7`，交付时 HEAD：`ba5e2f3a`。
- 工作树：`/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/fix-BL9105N-XXCCTXXE-260924`。
- 未触碰原有暂存改动 `scripts/check_nordic_sdk_dependency.sh`。工作期间它被外部提交为 `ba5e2f3a`；已核对该提交只改依赖检查脚本，不影响本次生产代码、测试或构建输入。本次功能改动尚未提交。
- 本轮仅修改测试与本文档。工作树已有 `SunSmart.xcodeproj/project.pbxproj`、设备能力及 JSON 配置改动，均保留用户当前状态。
- 上轮 15:06 构建使用 `SunSmartLocal.xcworkspace`，当时已核对 App、Pods 和本地 SDK 路径。
- 上轮 SDK realpath：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`；当时 HEAD：`ebbe1c9`、工作树干净。本轮不修改 SDK 或依赖声明。
- Space 实际入口：`SpaceMoreViewController → DeviceCategorysViewController → DeviceParameterDevicesViewController → DeviceParameterSettingsController`。
- Group 实际入口：`GroupViewController → ProfileSettingsViewController → ProfileSensitivityView`。

## 源码依据与实现

### 设备配置

在 [`devices_config.json`](../SunSmart/devices_config.json) 新增唯一的 `0A78/2322` 记录，使用用户提供的字段：`Driver Lighting`、3 个 element、`Lighting` 图标/设备分类、型号 `SRPL-BL9105N-XXCCTXXE`。

现有 `0x2132` 配置和型号保持不变。

### Absolute Sensitivity

[`Node+Capability.swift`](../SunSmart/Common/Data/Node+Capability.swift) 的产品排除集合新增 `0x2322`，仅对 CID `0x0A78` 生效。

[`MeshNetwork+SunSmart.swift`](../SunSmart/Common/Data/MeshNetwork+SunSmart.swift) 中现有 `Node.supportMotionSensitivity` 继续使用该规则；正常参数页的列表参数行、Filter、读取参数选择、Next 后模块及已有能力约束路径自然对齐 `0x2132`。其他厂商相同 PID 不受这条产品排除规则影响。

### Group 提示

在 [`Node+Capability.swift`](../SunSmart/Common/Data/Node+Capability.swift) 的 `externalLightSensorCapableLuminaireProductIdentifiers` 中增加 `0x2322`，保留原有产品，且不包含 `0x2131`。该规则仍严格限定 CID `0x0A78`。

[`ProfileSettingsViewController.swift`](../SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift) 保持原实现：当前 Profile 显示灵敏度卡片，且 Group 存在 `isExternalLightSensorCapableLuminaire` 成员时显示提示。空组、`group == nil`、成员顺序、在线状态不改变原有聚合语义；无需所有成员都属于目标型号。无需新增独立提示接口。

[`LightSensorCalibrationViewController.swift`](../SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift) 也使用该能力。因此，当 `0x2322` 具备对应日光传感器模型并进入适用的平面校准选择路径时，将显示外接光感连接确认提示；确认后继续原有启用流程。

[`ProfileSensitivityView.swift`](../SunSmart/Main/Profile/View/ProfileSensitivityView.swift) 仍只根据提示布尔值显示标签，滑条可编辑性继续由 `editable` 决定。原 [`提示设计`](260602_1808_profile_lack_sensitivity_notice.md) 也明确提示不影响保存或同步。

### 行为边界

[`Node+SyncData.swift`](../SunSmart/Common/Data/Node+SyncData.swift) 的相对灵敏度任务和 [`Node+MessageHandles.swift`](../SunSmart/Common/Data/Node+MessageHandles.swift) 的下发逻辑未修改。满足原有 Profile、Presence Sensor Model 等条件时，仍可生成相对灵敏度配置和退出组还原任务；本次不把源码路径存在当作硬件效果已验证。

分析阶段发现旧 `restoreData.motionSensitivityRange` 的部分任务/待同步判断未使用共享能力；这也是既有 `0x2132` 的边界。本次最终范围是与既有行为一致，未扩展修复这些旧恢复路径，不能宣称所有历史数据旁路均已拦截。

## 验证记录

- `bash scripts/check_up_down_light_product_support.sh`：本轮通过，输出 `UpDownLightProductSupportContractTests passed`、退出码 0。测试改为直接验证现有外接光感能力，覆盖 `0x2322` JSON 唯一性/字段、`0x2132` 和 `0x2322` 两项能力、`0x2131` 仅禁用绝对灵敏度、其他 CID 同 PID、缺 CID/PID，以及原产品名单和普通型号边界。
- 上述测试实际编译生产能力文件，SDK 使用既有轻量 stub；这不等于真实 Mesh 或 UIKit 页面验收。
- 本轮测试与文档的差异、格式和文档链接检查通过。
- 历史资源归属检查确认过五品牌共享 JSON、能力文件和 Profile 控制器；本轮未重新审查用户新增的工程文件改动。
- 历史 App 编译：2026-09-24 15:06 的旧实现曾输出 `BUILD SUCCEEDED`、退出码 0；此后生产实现和工程文件已变化，不能作为当前版本编译通过的证据。本轮仅修改测试和文档，未重新构建 App。
- 历史构建参数：`SunSmartLocal.xcworkspace` / `SunSmart` / `Debug` / `iphoneos` / `generic/platform=iOS` / `CODE_SIGNING_ALLOWED=NO`。
- DerivedData：`/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-fix-BL9105N-XXCCTXXE-260924`。
- 未自动安装、运行真机或请求服务端配置。

## 最短人工验收与发布配套

1. 进入 `0x2322` 的 Device Parameter Settings，确认列表、Filter、Next 均无 Absolute Sensitivity，其他参数保持正常。
2. 分别检查仅 `0x2322`、仅 `0x2132`、两者混合，以及与普通设备混合的 Group：适用 Profile 均显示同一句 **Some devices lack sensitivity**，有权限时仍可调整 Relative sensitivity。
3. 检查只读权限、Daylight / Manual Control、空组，以及不含任何原提示型号或 `0x2322` 的 Group：维持原有编辑和提示规则。
4. 在符合模型和校准模式条件时选择 `0x2322` 作为 daylight sensor，确认出现外接光感连接提示，取消/确认继续沿用现有行为。
5. 发布前确认使用地区/环境的服务端 `devicesConfig` 已包含 `0A78/2322`。App 启动可加载数据库配置，服务器返回又会替换内存列表，新增本地 JSON 不代表远端配置已发布。
