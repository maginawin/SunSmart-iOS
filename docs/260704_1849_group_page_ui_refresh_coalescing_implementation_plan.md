# Group 页面 UI 合并刷新实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Group 页面把高频设备和传感器状态更新合并为页面级周期 UI flush，避免设备 collection view 和 sensor table 滚动时被状态 UI 写入打断。

**Architecture:** `GroupViewController` 保留真实状态更新入口，但把 UI 写入改为 dirty marking + timer flush。`GroupSensorView` 只暴露 sensor table 滚动状态和批量刷新接口，具体调度仍由 controller 管理。

**Tech Stack:** Swift、UIKit、UITableView、UICollectionView、Timer、现有 `MeshLibManagerMessageDelegate` / `GroupSensorViewDelegate`。

---

## File Structure

- Modify: `SunSmart/Main/Group/Controller/GroupViewController.swift`
  - 增加 `refreshUIInterval`、dirty state、timer、flush helper。
  - 改 `didReceiveMessage` / `deviceDataUpdate` 为记录 dirty state。
  - 接入 collection view 滚动开始/结束，滚动期间跳过 timer flush。
  - 用户操作路径保留即时刷新，并顺延下一次 timer flush。
- Modify: `SunSmart/Main/Group/View/GroupSensorView.swift`
  - 给 `GroupSensorViewDelegate` 增加 table 滚动状态回调。
  - 增加批量刷新 sensor dirty events 的接口。
  - table 滚动结束通知 controller flush。
- Create: `scripts/check_group_page_ui_refresh_coalescing.sh`
  - 静态检查 Group 页刷新调度契约。

## Task 1: 静态回归脚本红灯

**Files:**
- Create: `scripts/check_group_page_ui_refresh_coalescing.sh`

- [ ] **Step 1: 新增脚本**
  - 检查 `GroupViewController.swift` 中存在 `refreshUIInterval`、dirty state、flush helper、scroll gating、immediate flush 顺延逻辑。
  - 检查 `didReceiveMessage` 中不再直接调用 `sensorView?.reloadSensorData(...)`。
  - 检查 `GroupSensorView.swift` 中存在 sensor table 滚动回调和批量刷新接口。

- [ ] **Step 2: 运行脚本确认失败**
  - Run: `bash scripts/check_group_page_ui_refresh_coalescing.sh`
  - Expected: FAIL，当前代码还没有方案 B 的统一调度。

## Task 2: GroupSensorView 增加滚动回调和批量刷新接口

**Files:**
- Modify: `SunSmart/Main/Group/View/GroupSensorView.swift`

- [ ] **Step 1: 扩展 delegate**
  - 增加 sensor table 开始滚动、结束滚动回调。

- [ ] **Step 2: 增加 dirty event 类型**
  - 在 `GroupSensorView` 内增加轻量 `SensorRefreshEvent`，包含 sensor、sensor type、是否是 transient trigger。

- [ ] **Step 3: 增加批量刷新接口**
  - 新增 `reloadSensorData(events:)`。
  - 批量刷新先更新 header，再仅更新可见 cell。
  - transient trigger 需要在 UI 刷新时短暂显示 triggered 状态，不能依赖 `Node.occupancyState` 的最终 false。

- [ ] **Step 4: 接入 table 滚动状态**
  - 实现 `scrollViewWillBeginDragging`、`scrollViewDidEndDragging`、`scrollViewDidEndDecelerating`。
  - 结束滚动时通知 controller flush。

## Task 3: GroupViewController 增加页面级调度状态

**Files:**
- Modify: `SunSmart/Main/Group/Controller/GroupViewController.swift`

- [ ] **Step 1: 增加状态字段**
  - `refreshUIInterval = 1.0`
  - dirty device address set
  - dirty sensor event storage
  - group summary dirty flag
  - full collection reload flag
  - scrolling flags
  - timer 和 next eligible flush date

- [ ] **Step 2: 增加 timer lifecycle**
  - `viewWillAppear` 启动 timer。
  - `viewWillDisappear` 和 `deinit` 停止 timer。

- [ ] **Step 3: 增加 flush helpers**
  - `markDeviceDirty`
  - `markSensorDirty`
  - `markGroupSummaryDirty`
  - `flushPendingUIUpdates`
  - `flushPendingUIUpdatesImmediately`
  - `deferNextScheduledUIFlush`

## Task 4: 改消息入口为 dirty marking

**Files:**
- Modify: `SunSmart/Main/Group/Controller/GroupViewController.swift`

- [ ] **Step 1: SensorStatus 改为记录 dirty sensor event**
  - 保持 `node.updateData(message:)`。
  - 不直接调用 `sensorView?.reloadSensorData(...)`。

- [ ] **Step 2: proximity trigger 记录 transient event**
  - 不再用“临时改 true -> 刷 UI -> 改 false”的立即刷新方式。
  - 记录 transient trigger event，flush 时由 `GroupSensorView` 显示 triggered。

- [ ] **Step 3: non-sensor device update 改为 dirty device**
  - 普通 device update 记录 device dirty + group summary dirty。
  - switch action 记录 full collection reload + group summary dirty。

- [ ] **Step 4: deviceDataUpdate 改为 dirty marking**
  - 页面可见时只记录 dirty device + group summary dirty。

## Task 5: 接入滚动 gating 和用户操作即时刷新

**Files:**
- Modify: `SunSmart/Main/Group/Controller/GroupViewController.swift`
- Modify: `SunSmart/Main/Group/View/GroupSensorView.swift`

- [ ] **Step 1: collection view 滚动 gating**
  - 开始拖拽标记 device collection scrolling。
  - 结束拖拽/减速后立即 flush 并更新 pageControl。

- [ ] **Step 2: sensor table 滚动 gating**
  - `GroupSensorViewDelegate` 回调里维护 sensor table scrolling。
  - sensor table 结束滚动后立即 flush。

- [ ] **Step 3: 用户操作即时刷新**
  - 点击设备、brightness/CCT/up-down ratio 等用户操作路径继续立即刷新。
  - 即时刷新后顺延下一次 scheduled flush。

## Task 6: 验证

**Files:**
- Run scripts and build only.

- [ ] **Step 1: 静态脚本通过**
  - Run: `bash scripts/check_group_page_scroll_jank_fix.sh`
  - Run: `bash scripts/check_group_page_ui_refresh_coalescing.sh`

- [ ] **Step 2: 空白检查**
  - Run: `git diff --check`

- [ ] **Step 3: iPhoneOS 构建**
  - Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

- [ ] **Step 4: 手工验证建议**
  - 83 设备 group 中滑动 collection view。
  - 展开 sensor 状态列表后滑动 table。
  - 停止滚动后 1 秒内看到最新状态。
  - 用户主动点击或拖动控制时仍立即反馈。
