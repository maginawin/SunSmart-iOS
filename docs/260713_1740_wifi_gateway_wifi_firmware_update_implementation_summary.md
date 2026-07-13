# WiFi Gateway WiFi Firmware Update 实施总结

## 实施范围

- WiFi Gateway（CID `0x0A78`、PID `0x2721`）右上角菜单的 `WiFi DFU` 进入 `WiFi Firmware Update` 页面。
- 新页面继承既有 `FirmwareVersionViewController`，仅通过受控钩子覆盖 WiFi 固件差异，保留后续独立实现升级流程的扩展边界。
- 当前 WiFi 固件版本固定显示为 `1.0.0`，不读取或删除本地固件缓存。
- 最新正式版和 Beta 测试版均在进入页面后查询，请求 `customerId` 使用 `wifi`；Beta 查询继续使用密码 `1314` 和 `profile=dev`。
- Beta Testing Environment 弹窗隐藏本地导入入口。
- 底部按钮显示 `UPGRADE`；仅当服务器版本高于 `1.0.0` 时可用，当前点击后显示既有开发中提示，不执行下载或升级。
- Firmware version history 沿用 `/sitespace/ota/history`，并从当前固件页面传入 `customerId=wifi`；Beta 状态同时沿用 `profile=dev`。

## 共享层调整

- `FirmwareVersionViewController` 增加页面标题、请求 customer id、当前版本、删除按钮可见性、Beta 导入入口、主按钮标题与主按钮动作等可覆盖钩子。
- 既有 BLE Firmware Version 默认行为保持不变，默认 customer id 仍为 `00`。
- `FirmwareVersionHistoryController` 增加默认值为 `00` 的字符串 customer id 参数，避免影响已有调用方。
- `BetaTestingAlertView` 增加默认显示导入按钮的配置，既有调用方行为保持不变。

## 国际化与 Target

- 新增英文和简体中文的 `WiFi DFU`、页面标题及 `UPGRADE` 文案。
- 新控制器已加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target 的 Compile Sources。

## 验证结果

- WiFi Firmware Update 静态契约完成红绿验证。
- WiFi Gateway 既有 10 个专项回归脚本全部通过。
- `project.pbxproj`、英文和简体中文 `Localizable.strings` 均通过 `plutil -lint`。
- `git diff --check` 通过。
- 以下 Debug iphoneos 构建均成功：
  - `SunSmart`
  - `Archipelago`
  - `SLG Sync Plus`
  - `SylSmart`

## 后续边界

- WiFi 固件真实当前版本获取方式仍待后续提供，届时替换固定的 `1.0.0`。
- `UPGRADE` 点击后的下载、传输、升级、进度和异常恢复流程不在本次范围内。
