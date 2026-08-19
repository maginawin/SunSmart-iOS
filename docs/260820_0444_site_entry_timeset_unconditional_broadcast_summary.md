# 进入 Site 后无条件广播 TimeSet 变更总结

## 变更结果

Owner 或 Editor 进入 Space 并首次连接到 Mesh 网络后，App 现在会在不检查 Schedule 的情况下延迟 3 秒向 `FFFF`（All Nodes）广播标准 Mesh `TimeSet`。

已移除原先的两个业务前置条件：

- 至少一个真实 Node 存在 `scheduleIds`；
- 至少存在一个已启用的 Schedule。

仍保留以下边界：

- 仅在当前 `DevicesViewController` 生命周期内首次 Mesh 连接时安排一次广播；
- Visitor 没有修改设备时间的权限，因此不安排广播；
- 延迟 3 秒发送，避免与进入页面后的设备状态查询冲突；
- 延迟执行时如果 Mesh 已断开，`syncTimeNodes()` 会直接跳过；
- 时区无法解析或无法编码为 Mesh 15 分钟步进偏移时跳过发送。

## 时区来源

广播继续统一通过 `SiteTimeSetMessageFactory.makeMessage(siteID:)` 生成：

1. 根据当前 Space 的 `siteId` 加载本地 Site；
2. 优先解析 `site.timezone`；
3. Site 不存在、时区缺失、格式非法或 Site 偏移无法编码时，仅对本次消息回退到手机当前时区；
4. 回退不会改写或上传 `site.timezone`；
5. 如果手机时区偏移也不能按 Mesh 的 15 分钟步进编码，则不发送。

## 权限与目标范围

本次移除了 Schedule 条件，并在自动广播入口落实已有权限边界：Owner、Editor 可以发送，Visitor 跳过。

目标地址仍为 `FFFF`，消息为标准 `TimeSet`（opcode `0x5C`）。广播发送不等待逐设备 `TimeStatus` 作为整体完成条件。

## 测试与构建

- `SiteTimeSetCallSiteContractTests`：通过；
- `SiteTimeSetMessageFactoryTests`：通过；
- `SiteTimeZoneValueTests`：通过；
- 修改文件 `git diff --check`：通过；
- SunSmart，Debug，generic iPhoneOS，无签名构建：通过；
- Archipelago，Debug，generic iPhoneOS，无签名构建：通过；
- SLG Sync Plus，Debug，generic iPhoneOS，无签名构建：通过；
- SylSmart，Debug，generic iPhoneOS，无签名构建：通过。

共享 DerivedData 在连续构建期间被其他 `SWBBuildService` 锁定，因此 SLG Sync Plus 与 SylSmart 的最终验证使用各自独立的 `/tmp` DerivedData 路径完成；没有终止外部构建进程，也没有修改工程配置。

## 尚未验证

自动化验证不能证明真实 BLE/Mesh 环境中的广播实际到达所有设备，也不能证明各固件收到 `TimeSet` 后都正确应用时间与时区。真机验收时应确认日志出现：

- `send message: TimeSet ... address: 65535`；
- `Sending TimeSet ... to: FFFF`；
- `Sending Access PDU (opcode: 0x5C, ...)`。
