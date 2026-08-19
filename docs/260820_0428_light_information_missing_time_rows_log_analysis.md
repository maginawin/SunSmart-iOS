# Light Information 未展示时间行 Log 分析

## 结论

该 Log 能确认页面由灯详情菜单进入 `DeviceInformationViewController`，但不能证明当前运行包已经包含“所有 Lights Information 均展示时间行”的最新代码。

如果用户确认页面滚动到底部后仍完全没有 `Date time` 和 `Time zone`，最可能原因是设备上运行的仍是更新前的构建。更新前的实现会在 `node.timeModel == nil` 时隐藏两行；当前源码只要求存在 Light Context，即使 `node.timeModel == nil` 也会追加两行并显示 `Not supported`。

2026-08-20 后续反馈：删除 App 后重新安装仍复现。这可以排除旧 App 数据缓存，但如果重新安装使用的是相同的旧产物、其他 worktree 或其他构建路径，仍不能排除安装产物不一致。

## Log 事实

1. `PJUIDebug` 显示从 `MenuPopView` 点击后进入了 `DeviceInformationViewController`。
2. 菜单 Cell 宽约 `141.33`，与 `DeviceLightViewController` 使用的 `SCRXFrom(140)` 相符，基本排除 `DeviceBaseViewController` 的 `SCRXFrom(114)` 菜单入口。
3. 页面进入后只发送了 `FirmwareUpdateInformationGet`，没有出现：
   - `TimeGet`；
   - `ConfigModelAppBind`；
   - Light 时间读取失败或离线相关协议日志。
4. RSSI 使用主 Element 地址 `0x0008`，Firmware Update Server 位于地址 `0x0009`，这是多 Element Node 的正常表现，不是时间行缺失原因。

## 与当前源码的对照

- `DeviceLightViewController.information()` 会无条件创建 `LightTimeInformationContext` 并传入 Information 页面。
- Information 数据源当前只判断 `lightTimeContext != nil`，随后必定追加两行。
- `node.timeModel == nil` 时，两行右侧均使用本地化的 `Not supported`。
- Light Coordinator 在 `node.timeModel == nil` 时不会创建，也不会发送 Binding 或 TimeGet。
- Table Data Source 的行数直接返回 `deviceInfoModels.count`，不存在仍固定为旧行数的问题。
- 四个 target 的 Swift File List 均包含 `LightTimeInformationCoordinator.swift`。
- 当前本地 SunSmart Debug iPhoneOS 产物包含 `LightTimeInformationCoordinator`、`lightTimeContext` 和 `not_supported` 字符串，生成时间为 2026-08-20 04:23。

因此，“没有 TimeGet”本身可以与“不支持 TimeGet”完全一致，但在当前源码中不应导致两行消失。

## 原因优先级

1. **安装产物与当前本地产物不一致**：最符合“没有 TimeGet且没有两行”的组合；删除重装不等于重新生成并安装了当前 worktree 的产物。
2. **时间行位于可视区域下方**：两行追加在 `Signal strength` 之后，需要确认已滚动到 Device Information section 底部。
3. **实际运行源码未注入 Light Context**：从菜单尺寸看概率较低，但仅凭现有 Log 无法百分之百排除其他构建分支或旧二进制。

## 建议复核

1. Clean/install 最新构建，避免只依赖设备上已有 App。
2. 进入同一设备 Information 后滚动到 `Signal strength` 下方。
3. 如果仍缺失，增加一次临时诊断日志，记录：
   - `lightTimeContext != nil`；
   - `node.primaryUnicastAddress`；
   - `node.timeModel` 的 Element 地址；
   - 最终 `deviceInfoModels` 的 row IDs。

这四项可以直接区分旧包、错误入口、能力缺失和数据源未追加，无需根据协议发送结果反推 UI 状态。

当前 Log 没有这些运行时字段，因此继续只分析同一份协议 Log 无法唯一确定根因。下一步需要用户确认是否允许加入临时诊断日志并重新复现。
