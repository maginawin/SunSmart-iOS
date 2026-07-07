# Device 文案国际化修复实施计划

## 目标

按已确认的方案 A 修复设备信息页和灯详情页中点名文案的国际化问题，范围仅限：

- `DeviceInformationViewController`
- `DeviceLightViewController`
- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`
- 聚焦回归脚本 `scripts/check_device_i18n_titles.sh`
- 既有图标回归脚本 `scripts/check_device_menu_icons.sh`

## 执行步骤

1. 新增脚本 `scripts/check_device_i18n_titles.sh`，检查：
   - `Version Identifier`、`Set Proxy`、`Reboot`、`Relay` 不再以 UI 硬编码方式出现。
   - `address`、`version_identifier`、`set_proxy`、`reboot`、`relay`、`PID` 在英文和中文 strings 中均存在。
   - `PID` 中文值为推荐的 `产品ID`。
2. 先运行脚本，确认当前失败。
3. 修改 `DeviceInformationViewController`：
   - `Version Identifier` 改为 `"version_identifier".localizedString`。
4. 修改 `DeviceLightViewController`：
   - `Set Proxy` 改为 `"set_proxy".localizedString`。
   - `Reboot` 改为 `"reboot".localizedString`。
   - `Relay` 改为 `"relay".localizedString`。
5. 修改英中 `Localizable.strings`：
   - 英文补齐 `version_identifier`、`set_proxy`、`reboot`、`relay`。
   - 中文补齐 `address`、`version_identifier`、`set_proxy`、`reboot`、`relay`。
   - 中文 `PID` 从 `产品id` 调整为 `产品ID`。
6. 运行 `scripts/check_device_i18n_titles.sh`，确认通过。
7. 更新 `scripts/check_device_menu_icons.sh` 中 Light 页 `Set Proxy` / `Reboot` 的 title 表达式，使其匹配本次 localizedString 改动；运行时如果仍失败，只记录 out-of-scope 的既有图标映射问题，不在本次修复菜单图标。
8. 运行 `git diff --check`。
9. 运行 iPhoneOS 构建：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## 非目标

- 不修改菜单图标、顺序、权限、回调或 Mesh 命令。
- 不扩大清理其他未点名硬编码。
- 不修改 target 配置或依赖。
