# EFC 设备页面国际化修复总结

## 修复范围

- 添加 EFC 虚拟设备入口：
  - `OthersViewController` 中的 `Emer&Fire Alarm\nController` 改为本地化 key。
- 添加/编辑 EFC 设备页面：
  - 页面标题、等待配置、事件标题与提示、恢复动作、亮度/倒计时/发送次数、LINK/LINKED、类型不匹配与禁止选择提示改为本地化。
- 编辑页进入的子页面：
  - EFC Monitor、Information、Linked 选择、状态图例、名称 cell 的可见文案改为本地化。
- EFC 右上角菜单进入的子页面：
  - EFC Sync 任务标题、repair 提示、同步进度页显示名改为本地化。
- 共享入口：
  - `DeviceAddTargetSelectView` 中 EFC 链接相关的 `Space`、`Battery Power Switch:`、`AC Power Switch:` 改为本地化。

## 本地化内容

- 在 `SunSmart/en.lproj/Localizable.strings` 和 `SunSmart/zh-Hans.lproj/Localizable.strings` 增加 EFC 专用 key。
- 补齐 zh-Hans 中已有英文 fallback key：
  - `emergency_event_ends`
  - `set_brightness_to_value`
  - `restore_auto`
  - `restore_none`

## 质量检查

- 新增 `scripts/check_efc_i18n.sh`，作为 EFC 可见英文硬编码的静态检查合约。
- 验证命令：
  - `bash scripts/check_efc_i18n.sh`
  - `git diff --check`
  - `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
  - `xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
  - `xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
  - `xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

以上检查均已通过。构建输出仍包含项目既有 warning，例如资源重名、Info.plist 位于 Copy Bundle Resources、重复 Compile Sources 条目；本次未改动这些既有配置。
