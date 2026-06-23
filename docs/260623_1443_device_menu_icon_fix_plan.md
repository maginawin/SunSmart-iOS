# Device Menu Icon Fix Plan

## 结论

问题真实存在，但影响面比“所有设备菜单”更窄：

- Light 设备的 DEBUG 菜单中，`Set Proxy`、`Identify`、`Reboot` 都被写成了 `menu_information`。
- Battery power switch / AC power switch 的菜单中，`Identify` 当前使用 `device_identify`，不符合这次要求的 `menu_identify`。
- WiFi Gateway 的 `Identify` 已经使用 `menu_identify`，无需修改。
- 普通 `DeviceBaseViewController` 和 DALI 页面当前没有 `Identify` 菜单项，只有 Information / Refresh / DALI Settings 等，不应为了本需求新增 Identify。
- Emergency Fire Controller 的右上角菜单当前只暴露 Information/Edit/Delete/Refresh，Identify 是页面中部 action button，不属于本次“右上角 options menu”修复范围。

## 代码证据

- `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`
  - `moreClick()` 中：
    - `Set Proxy` 使用 `menu_information`，应改为 `switch_proxy`。
    - `identify` 使用 `menu_information`，应改为 `menu_identify`。
    - `Reboot` 使用 `menu_information`，应改为 `menu_firmware_update`。
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
  - `moreAction()` 中：
    - `Identify` 使用 `device_identify`，应改为 `menu_identify`。
    - 该入口覆盖 Battery power switch 和 AC power switch，因为两者共用 `PJEightKeySwitchMonitorVC` / `PJEightKeySwitchMonitorViewModel`。
- `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
  - `Identify` 已使用 `menu_identify`。
- `SunSmart/Main/Device/Controller/DeviceBaseViewController.swift`
  - 当前菜单没有 Identify 项，不需要改。
- `SunSmart/Main/Device/Dali/Controller/DaliMasterViewController.swift`
  - 当前菜单没有 Identify 项，不需要改。

## 资源确认

以下资源均已存在：

- `SunSmart/Assets.xcassets/Device/switch_proxy.imageset`
- `SunSmart/Assets.xcassets/Common/menu_identify.imageset`
- `SunSmart/Assets.xcassets/Site/menu_firmware_update.imageset`
- `SunSmart/Assets.xcassets/Common/menu_information.imageset`
- `SunSmart/Assets.xcassets/Device/device_identify.imageset`

本次不需要新增图片资源，也不需要修改 target 配置或本地化文件。

## 修复方案

采用最小改动方案，只替换菜单项的图片资源名称，不改变菜单显示条件、菜单顺序、点击行为或权限逻辑。

1. 修改 `DeviceLightViewController.moreClick()`
   - `Set Proxy`: `menu_information` -> `switch_proxy`
   - `Identify`: `menu_information` -> `menu_identify`
   - `Reboot`: `menu_information` -> `menu_firmware_update`

2. 修改 `PJEightKeySwitchMonitorVC.moreAction()`
   - `Identify`: `device_identify` -> `menu_identify`

3. 不修改以下入口
   - `WiFiGatewayViewController`：已正确。
   - `DeviceBaseViewController`：无 Identify 菜单。
   - `DaliMasterViewController`：无 Identify 菜单。
   - `EmerFireAlarmMonitorRouting`：右上角菜单无 Identify。

4. 增加轻量回归脚本
   - 新增 `scripts/check_device_menu_icons.sh`。
   - 检查 Light 三个菜单标题对应的图标名称。
   - 检查 power switch Identify 菜单使用 `menu_identify`。
   - 检查 WiFi Gateway Identify 仍使用 `menu_identify`。

## 验证计划

1. 运行轻量脚本：
   - `bash scripts/check_device_menu_icons.sh`

2. 运行 diff 空白检查：
   - `git diff --check`

3. 运行 iPhoneOS 构建：
   - `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 风险与边界

- `Set Proxy` 和 `Reboot` 位于 `#if DEBUG` 内，本次只修 DEBUG 菜单图标，不改变 Release 行为。
- `Reboot` 使用 `menu_firmware_update` 是按需求指定的资源名，虽然语义上更接近 firmware/update 图标，但不另行引入新图标。
- `Identify` 标题在 Light 使用本地化 key，在 power switch / WiFi Gateway 使用硬编码 `Identify`，本次不处理文案国际化，避免扩大范围。
