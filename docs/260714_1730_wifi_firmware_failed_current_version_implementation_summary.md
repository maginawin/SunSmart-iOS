# WiFi Firmware Current Version Failed Display 实现总结

## 完成内容

- 将云端固件详情展示与主按钮 enablement 拆分为两个默认兼容 hook。
- WiFi Current version 为 `Failed` 时仍展示已获取的 latest 固件详情。
- Failed 状态继续显示 Refresh 并强制禁用 `UPGRADE`。
- Current version 有效时仍仅在 New version 严格更高时启用 `UPGRADE`。
- BLE/Mesh 固件页面继续使用父页面默认行为。

## 改动文件

- `scripts/check_wifi_gateway_firmware_update.sh`
- `SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift`
- `SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift`

## 验证结果

- WiFi Gateway 静态回归脚本：10/10 通过
- SunSmart iPhoneOS build：通过
- Archipelago iPhoneOS build：通过
- SLG Sync Plus iPhoneOS build：通过
- SylSmart iPhoneOS build：通过
- `git diff --check`：通过

## 范围说明

- 未修改 NordicSigMeshSDK、协议、网络接口、本地化、资源或 target 配置。
- 未实现真实 WiFi DFU；`UPGRADE` 继续沿用当前行为。
- Current version 为 `Loading...` 时的固件详情展示策略保持不变。
