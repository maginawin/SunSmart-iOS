# EFC 在线状态实时刷新设计

## 背景

EFC 的在线/离线展示不是独立缓存字段，而是通过 `DeviceEmerFireData.displayStatus` 实时读取绑定节点 `bindNode.state` 得出。当前列表 cell 已能按 `displayStatus` 展示在线、离线、修复、同步异常等状态，但页面刷新触发链路不完整。

## 当前问题

`DeviceOthersViewController` 监听了 Others 业务刷新、EFC 配置变更和 EFC 数据变更，但没有监听通用的 `deviceStateUpdateNotificationName`。当 `Node.state` 因 heartbeat、详情页退出或其他页面状态更新而变化时，Others 页面不会自动刷新 EFC item，导致在线/离线图标可能停留在旧状态。

`EmerFireAlarmMonitorVC` 打开和显示时会主动 `refreshRealState()`，并作为 `MeshLibManagerMessageDelegate` 处理 `deviceDataUpdate node`，所以当前详情页对自身 mesh 回调有刷新能力。但它同样没有监听 `deviceStateUpdateNotificationName`，与 Light/Switch 等页面的通用状态通知链路不一致。

## 目标

- EFC 绑定节点在线/离线状态变化后，Others 设备列表中的 EFC item 能实时更新。
- EFC 设备详情页收到当前绑定节点状态更新通知后，能同步切换离线、修复或重新读取真实状态。
- 改动保持在 EFC Others 列表和 EFC 详情页内，不修改协议、SDK、heartbeat 策略或设备状态判定模型。

## 推荐方案

采用局部监听和局部刷新：

1. 在 `DeviceOthersViewController.addNotificationObserver()` 增加 `deviceStateUpdateNotificationName` 监听。
2. 收到通知对象为 `Node` 时，按 EFC `bindNodeAddress` 匹配 `showItems` 中的 `.emergencyFireController`。
3. 命中后只刷新对应 collection item；如果 cell 可见则重新 `configCell(device:editing:)`，不可见则 `reloadItems(at:)`。
4. 在 `EmerFireAlarmMonitorVC` 增加同一通知监听，收到当前绑定节点后调用现有 `renderNodeAvailabilityChange(_:)`。
5. 保留现有 `refreshRealState()` 和 `MeshLibManagerMessageDelegate` 行为，避免改变当前详情页的主动读取逻辑。

## 非目标

- 不新增 Auth 信息。
- 不调整 EFC 协议解析或 `emergencyComprehensiveStatus` 重试策略。
- 不重构 `DeviceEmerFireData.displayStatus`。
- 不修改当前未提交的状态图例、资源或其他 UI 改动。

## 验证

- 代码检查：确认 Others 列表和 EFC 详情页都监听 `deviceStateUpdateNotificationName`。
- 代码检查：确认刷新只匹配 EFC 绑定节点，不影响 dongle 或其他设备类型。
- 构建验证：运行 iPhoneOS `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`。
