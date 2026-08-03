# Restore Device Data EFC 缺少图标分析

**日期：** 2026-08-03
**结论：** Restore Device Data 中的 EFC Controller 应展示现有 EFC 主图标资源 `emergency`，不应使用按配置自动拼接的 `device_EmergencyController`。

## 1. 当前表现与根因

`CID 0x0A78 / PID 0x2131` 在 `devices_config.json` 中的 `iconCategory` 为 `EmergencyController`，因此通用 `Node.iconName` 会生成 `device_EmergencyController`。

当前资源目录不存在名为 `device_EmergencyController` 的图片，`UIImage(named:)` 返回空，因此 Restore Device Data 设备行没有图标。

Restore 页存在两个受影响入口：

- 尚未扫描到设备时，设备行直接加载历史 Node 的 `node.iconName`；
- 扫描到设备后，先把 `node.iconName` 复制给 `ProvisioningDevice.icon`，随后虽把设备分类更新为 `.emergencyController`，但没有重新映射 EFC 图标。

## 2. 应展示的图标

应使用 `EmergencyFireControllerIconName.main`，其资源名称为 `emergency`。该图标是黄色应急警报灯造型，中间包含火焰符号。

这是项目中已经确定的 EFC Controller 主图标，并已用于：

- Classic Add Device；
- Professional Add Device；
- Device Reset/Force Reset；
- EFC 专用同步列表；
- EFC Firmware 设备列表。

因此 Restore Device Data 应与上述入口保持一致，不新增图片资源，也不直接硬编码另一套图标名称。

## 3. 建议修复范围

最小修复是在 Restore 设备行的两条图标来源上统一使用 `EmergencyFireControllerIconName.addListIconName(for:fallback:)`：

- 历史 Node 展示：根据已注册设备类型选择 `emergency`，其他设备继续使用 `node.iconName`；
- 扫描设备展示：先完成注册表类型映射，再用同一 helper 设置 `ProvisioningDevice.icon`。

这样可以覆盖扫描前和扫描后两个状态，同时保持普通设备当前图标逻辑不变。无需修改资源、本地化或 NordicSigMeshSDK。
