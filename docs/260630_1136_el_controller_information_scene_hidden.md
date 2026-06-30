# EL Controller Information 隐藏 Scene 行修复记录

## 背景

CID `0x0A78`、PID `0x24C1` 的 EL Controller 设备会命中 `node.isEmergencySignController`。该设备从 Light 详情页进入共享 `DeviceInformationViewController` 时，入口原本使用默认初始化参数，因此 Information 页面仍展示 `Scene` 区块和 Scene 列表行。

## 根因

`DeviceInformationViewController` 已支持通过 `showsSceneSection: false` 隐藏整个 Scene 区块。WiFi Gateway、EFC 等入口已经复用该能力，但 `DeviceLightViewController.information()` 仍直接调用 `DeviceInformationViewController(node:)`，没有把 EL Controller 的能力差异传给共享 Information 页面。

## 修复

在 `DeviceLightViewController.information()` 中使用 `!node.isEmergencySignController` 计算 `showsSceneSection`，并传入共享 `DeviceInformationViewController`。

该修复只影响 Light 详情页打开 Information 的 Scene 区块可见性：

- EL Controller / `isEmergencySignController == true`：隐藏 `Scene` 区块和 Scene 列表行。
- 普通 Light：保持默认展示逻辑。
- 不修改 `isEmergencySignController` 判定，也不影响已有 WiFi Gateway、EFC、Power Switch 的 Information 入口。

## 验证

- `bash scripts/check_el_controller_information_sections.sh`
- `bash scripts/check_device_information_menu_transition.sh`
