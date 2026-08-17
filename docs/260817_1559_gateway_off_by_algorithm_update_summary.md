# Gateway Off by 算法更新总结

## 更新结果

Gateway 详情页的 `Off by` 已统一为：

`Gateway datetime − Local datetime`

- Gateway 时间领先 Local 时，显示正值。
- Gateway 时间落后 Local 时，显示负值。
- 双方 datetime 均为应用各自 Offset 后的墙钟时间，因此 Site 与 Gateway 时区不一致仍会体现在差值中。

页面取得有效 TimeStatus 样本后保存该差值。后续 0.5 秒 Tick 使用 `Gateway = Local + Off by` 推进 Gateway 行，不重复发起蓝牙读取。

## 改动范围

- 调整 `GatewayDetailClockCore.offBySeconds` 的相减方向。
- 调整 `GatewayDetailClockCore.gatewayDisplayDate` 的持续展示推算方向。
- 更新纯逻辑测试，覆盖 Gateway 落后 8 小时、领先 90 秒及持续展示方向。
- 同步修正 Gateway Time Zone 分析与实现总结中的公式。

未修改本地化、资源、target 配置、Mesh TimeGet/TimeSet、同步成功阈值或云同步流程。

## 验证结果

- `GatewayDetailClockCoreTests`：通过。
- `git diff --check`：通过。
- iPhoneOS generic device、Debug、关闭签名构建：
  - SunSmart：通过。
  - Archipelago：首次受短暂 `build.db` 锁影响，串行重试后通过。
  - SLG Sync Plus：通过。
  - SylSmart：通过。

## 未覆盖

- 未进行真实 Wi-Fi/4G Gateway 的 BLE/Mesh 联调。
- 未进行四品牌真机页面视觉与动态时间观察。
