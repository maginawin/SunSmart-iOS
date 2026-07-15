# WiFi Gateway 固件升级实现总结

## 实现范围

- SDK 的 `43 10` 已同步为新版 `URL + firmware_id` payload，移除 SHA256 和 size 字段，并按新版公式校验完整业务 payload 不超过 256 字节。
- App 根据当前区域的 HTTPS base URL 生成 HTTP 下载地址，固定拼接 `/sitespace/ota/download?key={filename}`。
- 云端 `version` 仅移除最多一个前导 `v/V` 后作为 `firmware_id`。
- WiFi Firmware Update 页面已接入 `43 10`、`43 11` 和 `43 14`，支持开始升级、状态轮询、主动进度上报、当前版本查询和最终版本同步。
- 新增 `WiFiFirmwareUpdatingView`，覆盖连接超时、服务器不可用、下载中、下载失败、更新中、更新失败和更新成功状态。
- downloading 和 updating 均显示不可点击的 CANCEL；失败显示 UPGRADE AGAIN；成功显示 DONE。
- Current version 查询失败时仍展示 New version，但 UPGRADE 保持不可用。
- 页面内容使用 UIScrollView，升级状态区域与 Current version 间距 32 pt、左右边距 36 pt，不使用缩放宏。
- DFU 会话按 Mesh network UUID 和 node address 持久化，页面返回或 App 重启后先查询 `43 11` 恢复本轮状态。

## 状态与轮询规则

- `43 10` ACK 等待期间使用现有 Loading HUD。
- `43 10 00` 后立即建立本轮本地会话，并以 downloading 0% 作为首次状态，随后查询 `43 11`。
- 正常轮询间隔 2 秒，单次 `43 11` 超时 5 秒；连续 3 次查询失败后降频为 10 秒。
- 同一协调器内不允许 Mesh 请求重叠，主动上报与轮询结果进入同一状态处理入口。
- `43 11` 查询临时失败时保留最后状态并继续轮询，不把通信失败误判为 OTA 失败。
- 只有本地已接受会话且 `firmware_id` 匹配时，设备状态才归属于本轮升级。
- SUCCESS 优先使用 `module_version` 更新 Current version；缺失时回退到本轮 `firmware_id`。
- DONE 清理本轮持久化状态并回到默认版本比较 UI。

## 验证结果

- NordicSigMeshDemo generic iPhoneOS 构建通过。
- SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 generic iPhoneOS Debug 构建通过。
- 10 项 WiFi Gateway 静态回归脚本全部通过。
- `project.pbxproj`、英文和简体中文本地化文件均通过 `plutil -lint`。
- App 与 SDK 仓库均通过 `git diff --check`。
- SDK `swift test --filter WiFiGatewayVendorMessageTests` 在当前 macOS SwiftPM 环境仍被 SDK 既有 UIKit 依赖阻断，错误为 `no such module 'UIKit'`；本次以 SDK 协议测试源码、NordicSigMeshDemo 和四个 App target 的 iPhoneOS 构建作为编译验证。

## 尚需实机验证

当前会话没有连接可控 WiFi Gateway，以下项目不能用静态检查或构建冒充实机证据：

- `43 10` 全部 ret 值与 Mesh transport timeout。
- downloading、verifying、rebooting、recovering、version check 等状态转换和主动上报。
- App 前后台、返回页面和 App 重启后的真实会话恢复。
- firmware ID mismatch、终态保留、module version 最终同步。
- 小屏设备的实际滚动、Loading HUD 和各状态视觉还原。

## 提交记录

SDK：

- `41c9a62 feat: update wifi gateway dfu metadata`

App：

- `b0ff5beb feat: add wifi firmware dfu state model`
- `f18e6604 feat: add wifi firmware dfu coordinator`
- `2bcb985d feat: add wifi firmware updating view`
- `65b30682 refactor: add wifi firmware page hooks`
- `07b71098 feat: enable wifi gateway firmware upgrade`
- `099f286d fix: retain wifi dfu state during status timeout`
- `0b1e6c70 fix: serialize wifi dfu status handling`
