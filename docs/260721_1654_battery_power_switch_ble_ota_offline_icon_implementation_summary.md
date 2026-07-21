# Battery Power Switch BLE OTA 离线图标优化实施总结

## 实施结果

- 仅调整 Firmware update via BLE 设备列表中的 Battery Power Switch 离线图标。
- 在线状态继续使用 `device_BatteryPowerSwitch`。
- 未被 BLE 扫描找到时使用 `device_offline_BatteryPowerSwitch`。
- 离线资源加载失败时回退到灰色在线图标。
- AC Power Switch、其他设备及 BLE OTA 流程保持不变。

## 改动范围

- `SunSmart/Main/Firmware/View/BleFirmwareTypeUpdateViewCell.swift`
- 未修改资源、本地化、target 配置、依赖或 NordicSigMeshSDK。

## 验证

- 在线、离线及非 Battery Power Switch 源码契约检查：通过。
- Battery Power Switch 在线/离线资源存在性和 Asset Catalog JSON 检查：通过。
- `git diff --check`：通过。
- SunSmart Debug iPhoneOS 构建：通过，输出 `BUILD SUCCEEDED`。

## 未覆盖项

- 未连接 Battery Power Switch 真机验证 BLE 扫描在线/离线切换效果；需要在具备对应设备的环境中完成运行时验收。
