# BL9036T-PCBA Emergency Sign Controller 设计说明

## 背景

本次新增的设备为 `SR-BL9036T-PCBA`，SIG Mesh 产品信息为 Company ID `0x0A78`、Product ID `0x24C1`。`devices_config.json` 中该设备已配置为：

- `categoryName`: `EL Controller`
- `elementCount`: `3`
- `iconCategory`: `EMSign`
- `deviceCategory`: `Lighting`
- `modelName`: `SR-BL9036T-PCBA`

协议基础属性参考 `protocols/0x24C1.json`。该设备在 Mesh composition 中包含 on/off、lightness、CTL 等灯相关 model，但产品功能上不支持普通灯控，只支持 Identify 以及基础 Mesh 能力，例如 OTA / firmware 信息、proxy、relay、friend。

Figma 单设备控制页参考：

`https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-drafts?node-id=75-7576&t=t1333zKaVG0rYOOi-11`

## 目标

- 将 `0x24C1` 作为 Lighting 设备加入现有添加、Space、Group、Scene、Schedule 通路。
- 单设备控制页使用 Identify-only UI，不展示或触发 on/off、brightness、CCT 等普通灯控。
- Identify 命令使用与现有灯类型设备一致的 vendor identify。
- 入网默认名称使用 `EM1`、`EM2` 递增，独立于普通灯的 `L1`、`L2`。
- Device Parameter Settings 完全排除该设备，包括 All devices 批量参数列表和单独 PID 分类。
- 使用 `EMSign` 系列设备图标，包括中心图标 `device_center_EMSign`。
- 保持 Group、Scene、Schedule 中的现有灯控展示与命令逻辑，不为该设备新增过滤。

## 非目标

- 不新增独立 `Node.DeviceType`。
- 不重写组、场景、日程、同步、OTA 或 firmware 页面。
- 不在当前阶段屏蔽组级 on/off、auto、调光、调色、test 等命令。
- 不调整 `protocols/0x24C1.json`。
- 不处理 `user-temp/`。

## 推荐方案

采用“轻量产品 Profile”方案。

系统层继续让 `0x24C1` 解析为 `Node.DeviceType.light`，以保留 Lighting 设备在添加、分组、场景、日程、同步、OTA 和 firmware 相关流程中的既有行为。与此同时，为 `companyIdentifier == 0x0A78 && productIdentifier == 0x24C1` 增加一个小范围产品识别能力，例如 `isEmergencySignController` 或 `supportsOnlyIdentifyControl`，只在确实需要特殊处理的边界使用。

这个方案比新增独立 DeviceType 风险更低，也比在多处散落裸 PID 判断更容易维护。未来如果出现同类设备，只需要把 PID 加入同一 Profile 集合。

## 产品 Profile 边界

`0x24C1` 的特殊边界如下：

- 保留 `.light` 身份。
- `defaultNameCategory` 返回 `EM`。
- `supportSetParameter` 返回 `false`。
- 单设备控制页切换到 Identify-only UI。
- 单设备 Identify 使用 vendor identify。
- 图标仍由 `iconCategory = EMSign` 驱动。

其它 Lighting 行为保持不变：

- 扫描和添加分类继续显示在 Lights。
- 可以加入 Site、Space、Group。
- 加入组后仍按现有 Model 和 group sync 逻辑发送配置和订阅命令。
- Scene 和 Schedule 中仍可作为普通灯参与选择和配置。
- Group 页面中的 on/off、auto、slider、test 等控件不对该设备做额外过滤。

## 单设备控制页

`DeviceLightViewController` 需要根据产品 Profile 切换 UI。

普通 Lighting 设备继续使用现有灯控 UI。`0x24C1` 使用 Identify-only UI：

- 标题显示设备名称，例如 `EM1`。
- 背景沿用 Figma 的浅色页面和中央灯光光圈视觉。
- 中央图标使用 `device_center_EMSign`。
- 默认视觉状态为 ON，不根据 `node.isOn` 切换到 off 样式。
- 隐藏 on/off 按钮。
- 隐藏 brightness 和 CCT 状态展示。
- 隐藏 brightness 和 CCT slider。
- 下方只保留 Identify 按钮。
- 离线或未 key bind 完成时，仍沿用现有离线 / repair 空态。
- 更多菜单、设备信息页、刷新和删除 / 编辑入口沿用现有权限与交互。

Identify 行为：

- 点击 Identify 后，使用与现有灯类型设备一致的 vendor identify。
- 命令目标为 `node.sunricherVendorModel`。
- 不发送普通灯控的 on/off、lightness、CCT 命令。
- 如果设备离线、未 key bind 或缺少 vendor model，不发送 Identify 命令，并按现有页面风格禁用或提示。

## 命名

新增设备入网后通过现有 `getNextNodeName` 机制分配名称。Profile 对 `0x24C1` 返回默认名前缀 `EM`，因此结果为 `EM1`、`EM2`。

编号规则：

- 只避开当前 Mesh 中已存在的 `EM数字` 名称。
- 用户手动改名为 `EM1` 时，新设备从 `EM2` 开始。
- 普通灯名称如 `L1` 不影响 EM 编号。

## Device Parameter Settings

`0x24C1` 需要从 Device Parameter Settings 完全移除。

实现边界：

- `supportSetParameter` 对该 Profile 返回 `false`。
- `DeviceCategorysViewController` 当前基于 `node.supportSetParameter` 构建数据源，因此该设备不会进入 `allDevices`。
- 结果是 All devices 批量参数列表和单独 PID 分类都不展示 `0x24C1`。

该规则只针对 Device Parameter Settings。设备信息页仍可展示 PID、model、device type、firmware 等普通信息。

## 图标资源

`devices_config.json` 使用 `iconCategory = EMSign` 后，现有图标命名规则会解析为：

- 在线图标：`device_EMSign`
- 离线图标：`device_offline_EMSign`
- 待同步图标：`device_unsync_EMSign`
- 单设备中心图标：`device_center_EMSign`

资源目录已按 `device_offline_EMSign` 修正。实现计划中只需要做静态校验，确认这些资源可被 `UIImage(named:)` 找到。

## 数据流

添加流程：

1. 扫描时根据 `devices_config.json` 将 `0x24C1` 解析为 `.light`。
2. 入网完成后设置 MAC、RSSI 和默认名称。
3. 默认名称前缀通过产品 Profile 得到 `EM`。
4. 添加后仍执行 Lighting 默认配置和可选 group sync 逻辑。

控制页流程：

1. 打开 `DeviceLightViewController`。
2. Controller 识别 `node.isEmergencySignController`。
3. 在线且 key bind 完成时展示 Identify-only UI。
4. 点击 Identify 时发送 vendor identify。
5. 设备状态回包只刷新离线 / RSSI / 基础状态，不驱动普通灯控 UI。

参数设置流程：

1. `DeviceCategorysViewController` 遍历 `MeshNetworkManager.instance.realNodes`。
2. `0x24C1` 的 `supportSetParameter` 为 `false`。
3. 该设备不加入 `allDevices`，也不加入 PID 分组。

## 错误处理

- 离线：单设备页显示现有 offline 空态，不展示 Identify-only 控制按钮。
- 未 key bind：显示现有 repair 空态。
- 缺少 vendor model：Identify 不发送命令，并按现有 HUD 风格提示或禁用按钮。
- 资源缺失：不崩溃，优先复用项目现有 fallback；实现阶段需要通过静态检查避免缺失。
- 未来新增同类 PID：只扩展产品 Profile 的 PID 集合，不复制页面判断。

## 测试与验证

静态验证：

- 确认 `SunSmart/devices_config.json` 中 `0x24C1` 为 `iconCategory = EMSign`、`deviceCategory = Lighting`。
- 确认 `protocols/0x24C1.json` 可作为协议参考，不被本次改动修改。
- 确认 `device_EMSign`、`device_offline_EMSign`、`device_unsync_EMSign`、`device_center_EMSign` 资源存在。
- 确认 `0x24C1` 仍解析为 `.light`。
- 确认 `defaultNameCategory` 对 `0x24C1` 返回 `EM`。
- 确认 `supportSetParameter` 对 `0x24C1` 返回 `false`。
- 确认单设备 Identify-only 分支不调用 on/off、lightness、CCT 发送接口。

构建验证：

- 按项目规则运行 iOS 真机构建校验：
  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

人工验证建议：

- 新入网 0x24C1，默认名称为 `EM1`。
- 再入网第二个 0x24C1，默认名称为 `EM2`。
- 打开单设备页，只看到 Identify 控制。
- 点击 Identify，设备执行与普通灯相同的 vendor identify 效果。
- Device Parameter Settings 不出现该设备。
- 将设备加入 Group 后，Group / Scene / Schedule 仍按普通灯展示控件。

## 影响文件范围

预计实现涉及：

- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`
- `SunSmart/Main/Device/Parameter/Controller/DeviceCategorysViewController.swift`
- `SunSmart/Common/Mesh/Device/MeshDeviceConfigInfo.swift`，仅静态确认图标命名规则
- `SunSmart/devices_config.json`，仅静态确认已有配置
- `SunSmart/Assets.xcassets/Device/...`，仅静态确认已有资源

如实现阶段发现单设备页拆分成本过高，可以在 `DeviceLightViewController` 内部增加私有 Identify-only setup/update 分支，避免扩大重构范围。
