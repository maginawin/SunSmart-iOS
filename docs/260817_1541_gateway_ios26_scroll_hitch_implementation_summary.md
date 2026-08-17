# Gateway 页面 iOS 26 滚动卡帧修复实施总结

## 实施结果

已按确认的方案 A 完成代码修改，保留 Gateway Clock 0.5 秒显示节奏、Wi-Fi RSSI 5 秒轮询、Mesh Heartbeat、Proxy Ready 和请求串行语义，同时移除了两条周期链对 `UITableView` 的结构刷新。

## 本次修改

### Gateway Clock

- Clock Timer 从 `.common` RunLoop 改为 `.default`，手指 Tracking 期间不再触发 Tick。
- Dragging、Tracking、Decelerating 期间只保留最新时间，不更新 Cell；滚动结束后补一次最新显示。
- Tick 不再调用 `reloadRows`，只原位更新当前可见的 Gateway、Local 两个时间 Cell。
- Off by/Sync 操作行不再参与每 0.5 秒 Tick。
- 新增可复用的 `GatewayDetailClockFormatter`，页面持有同一个 Formatter，避免每个 Tick 重复创建 `DateFormatter`。

### Wi-Fi RSSI

- 自动 `0x43/0x0F` RSSI 请求使用独立的 `backgroundInteractionLock` 展示策略。
- 自动 RSSI 请求开始、结束不再调用 `reloadSection(.networkConnectivity)`。
- 请求期间只临时关闭当前 Network Connectivity Cell 的交互，不重设 SSID、Password、焦点和约束。
- 用户主动请求和真正改变连接内容的流程继续保留原有 Section 刷新语义。

### Header

- `WiFiHeaderStatus` 增加语义去重；Icon 和状态文案均未变化时不重复更新 Header。
- `GatewayHeaderStatusItemView` 缓存 Title 展示模式和 Icon Size；布局形态未变化时不再重建 SnapKit 约束。
- `-47 dBm` 到 `-53 dBm` 仍属于 Excellent，不再产生重复布局。

### 回归契约

- 新增 `GatewayScrollPerformanceContractTests.swift`。
- 新增 `scripts/check_gateway_scroll_performance.sh`。
- 契约覆盖 Clock RunLoop、滚动态门控、无 `reloadRows`、Formatter 复用、RSSI 非结构刷新、输入 Cell 轻量锁定及 Header 去重。

## 验证结果

通过：

- Gateway Scroll Performance contracts。
- Wi-Fi Gateway Header/RSSI contracts。
- Gateway Detail Clock Core tests。
- `git diff --check`。
- `SunSmart` generic iPhoneOS unsigned build。
- `Archipelago` generic iPhoneOS unsigned build。
- `SLG Sync Plus` generic iPhoneOS unsigned build。
- `SylSmart` generic iPhoneOS unsigned build。

四个 Target 均使用 `iphoneos26.5` SDK，结果为 `BUILD SUCCEEDED`。

## 工作区并行改动说明

本轮进行期间，工作区出现了另一组 Gateway Clock Syncing 动画相关改动，包括：

- `Tests/Device/GatewayDetailClockCoreTests.swift`
- `Tests/Device/GatewayDetailClockRuntimeContractTests.swift`
- `scripts/check_gateway_information_time.sh`
- `gateway_clock_sync_loading.imageset`
- `GatewayViewController`、`GatewayDetailClockCoordinator` 中的 pending sync/complete sync 部分

这些内容不是本次滚动修复创建的，已全部保留。四 Target 编译已证明两组当前源码可以共同编译。

综合 `scripts/check_gateway_information_time.sh` 当前仍会停在该独立改动的未完成契约：业务源码尚未包含 `updateSyncingAppearance(isSyncing: true)`。本次没有越权补做或删除该 Syncing 动画功能。

## 尚未覆盖

- iOS 26 真机快速滑动、慢速拖动、减速和底部回弹验收。
- Instruments Core Animation Hitches/Time Profiler 前后对比。
- 实际 BLE/Mesh 下 RSSI 回包恰好发生在滚动期间的帧率验证。
- 4G Gateway 真机 Clock + Signal 并行刷新验证。

构建和静态契约通过不等同于真机性能验收；下一步应在原复现设备上重点验证滚动期间不再出现周期性停顿或列表跳位。
