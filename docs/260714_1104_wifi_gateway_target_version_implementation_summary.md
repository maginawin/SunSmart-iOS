# WiFi Gateway Current Target Version 实施总结

## 实施结果

- 移除 WiFi Firmware Update 页面中的固定版本 `0.0.1`。
- `Current target version` 展示本次正式或 dev 查询返回的有效固件版本。
- 每次查询前清除上一次 WiFi 服务器结果；服务器无固件、网络失败或格式无效时展示 `None`。
- WiFi 有有效服务器固件时独立判定为可升级，不再将服务器版本与自身比较。
- `UPGRADE` 继续使用现有开发中提示，未实现真实升级。

## 共享层边界

- `FirmwareVersionViewController` 新增默认关闭的请求前结果重置 hook。
- `FirmwareVersionViewController` 新增默认沿用数值版本比较的新固件判断 hook。
- BLE、Mesh 固件页面未覆盖这些 hook，既有行为保持不变。

## 验证结果

- WiFi Firmware Update 聚焦契约完成两阶段 RED 和最终 GREEN 验证。
- Gateway/WiFi Gateway 共 12 个专项脚本全部通过。
- `git diff --check` 通过。
- 以下 Debug iPhoneOS 构建全部成功：
  - `SunSmart`
  - `Archipelago`
  - `SLG Sync Plus`
  - `SylSmart`
