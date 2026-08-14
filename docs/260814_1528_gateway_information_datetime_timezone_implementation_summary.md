# Gateway Information Date Time 与 Time Zone 实现总结

## 实现结果

- 4G Gateway 与 WiFi Gateway 的 Information 页面在 Signal strength 后增加 Date time 与 Time zone。
- 页面进入及点击任一时间行时，仅在当前 direct Proxy Ready 确认连接到同一 Gateway 后发送 TimeGet。
- 有效 TimeStatus 按 Gateway 返回的 timestamp 与 timezoneOffset 更新界面和本地 Node，并立即通过 Gateway Register 同步对应 Cloud Gateway 快照。
- Information 流程不读取、不修改 Site 根级 timezone，不调用 Site Props 或 Site 同步接口。
- 未连接时显示“Gateway not connected / 网关未连接”和“--”；读取失败保留上一次有效值并提示一次失败。
- Fast Add 的 4G/WiFi Gateway 共用分支在全部配置与 Attention 后追加一次使用 Site fixed Offset 的 TimeSet。
- Fast Add TimeSet 失败或返回值无效时不回滚 Gateway 添加，Node 保持 timezone 为 nil、timestamp 为 0，Cloud export 省略 timezoneOffset 与 timestamp。
- WiFi Gateway 页面在 Proxy Ready 后不再自动发送 TimeSet，仅保留网络信息自动加载门闩；后续时间修正仍由 Sync Gateways 页面负责。

## 自动化与静态验证

- Gateway 时间格式化与读取 attempt 核心测试通过。
- Gateway Information runtime、页面行、本地化与四 target membership contract 通过。
- Fast Add TimeSet 策略、失败清空与 Cloud 字段省略 contract 通过。
- WiFi automatic-load gate 测试与 Proxy Ready no-TimeSet contract 通过。
- 既有 Sync Gateways、Gateway Information、菜单转场、WiFi Server Information recovery 回归脚本全部通过。
- English 与简体中文 Localizable.strings 均通过 plutil 校验。
- project.pbxproj 通过 plutil 校验；禁止 Site timezone 写入边界搜索无命中；git diff --check 无错误。

## 构建验证

以下 Debug generic iPhoneOS、CODE_SIGNING_ALLOWED=NO 构建均成功，并使用本地 NordicSigMeshSDK：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

构建日志中的 Info.plist Copy Bundle Resources 和 FSCalendar 重复 Sources 警告为工程既有告警，不属于本次改动。

## 待真机与服务器验收

- 4G/WiFi Information：已连接进入自动读取、未连接文案、点击重试、连续点击去重、超时、seconds 为零、断开、正负 Offset、页面退出后的回包恢复。
- 4G/WiFi Fast Add：TimeSet 成功；TimeSet 失败仍添加成功；失败 Gateway 的上传 payload 省略两个时间字段。
- WiFi Gateway：Proxy Ready 不发送 TimeSet，但网络信息仍自动加载。
- Sync Gateways：可修正 Fast Add 初始化失败的 Gateway。
- 真实服务器：通过 siteprops 回读确认成功路径只更新对应 gateways 项；失败路径确认服务器对缺失时间字段的实际保留或清理语义。

静态测试、构建成功、本地持久化或 HTTP 成功均不能替代上述 BLE/Mesh 真机与服务器持久化验收。
