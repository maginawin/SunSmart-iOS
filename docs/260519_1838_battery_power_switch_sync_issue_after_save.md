# Battery Power Switch SAVE 后仍显示 Sync Issue 分析

## 现象

在 Switches 页面中，Battery Power Switch 显示为需要同步。进入该 BPS 的 Edit 页面，SAVE 同步成功后返回 Switch 页面，再回到 Switches 页面，BPS 卡片仍显示需要同步。

## 数据流

1. Edit 页面 SAVE 入口：
   - `PJPreAddEightKeySwitchesVC.submitBatteryPowerSwitch(_:)`
   - 需要同步时 push `SyncDevicesViewController(type: .batteryPowerSwitch(switchData))`

2. SAVE 成功回调：
   - `switchData.markBatteryPowerSwitchSyncSucceeded()`
   - `persistSwitchData(switchData)`
   - `PJEightKeySwitchRepository.shared.save(switchData)`
   - `NotificationCenter.default.post(name: switchsRefreshNotificationName, ...)`

3. Switches 页面展示：
   - `DeviceSwitchesViewController.cellForItemAt`
   - `PJEightKeySwitchRepository.shared.makeEightKeySwitch(from:)`
   - `PJEightKeySwitchesViewCell.configure(...)`
   - `PJEightKeySwitchData.displayStatus`

## 根因

`PJEightKeySwitchData.displayStatus` 当前对已绑定开关的 sync issue 判断是：

- `needSyncData || needsBatteryPowerSwitchSync`

其中：

- `needsBatteryPowerSwitchSync` 是 BPS 专属状态，使用 `syncState/desiredConfigHash/appliedConfigHash` 判断。
- `needSyncData` 是旧 `DeviceSwitchData` / Kinetic Switch 同步状态，调用 `getNeedSyncDatas()`，再按 `switchKeys` 推导 EnOcean proxy、target model subscription 是否缺失。

BPS SAVE 成功后，`markBatteryPowerSwitchSyncSucceeded()` 会把 BPS 专属状态写成 synced，`appliedConfigHash = desiredConfigHash`，因此 `needsBatteryPowerSwitchSync` 应为 false。

但 BPS 仍继承 `DeviceSwitchData`，且 Edit 保存时会设置：

- `panelType = .scenes_4key` 或 `.default_4key`
- `linkGroupAddress = BPS virtual group`
- `bindGroupAddresses = target groups`

于是旧 `needSyncData` 会把 BPS 当作 Kinetic Switch 继续计算：

- `.scenes_4key` / `.default_4key` 的 `switchKeys` 包含 dim 和 CCT long press 规则。
- `getEnOceanSubscriptionMessageHandles(switchKeys:)` 会检查 `levelModel` 与 `ctlTemperatureLevelModel` 是否订阅 `linkGroupAddress`。
- BPS K8 面板不支持 CCT，之前已经明确不应订阅 CCT model。
- 因此 target device 上缺少旧 Kinetic Switch 预期的 CCT model subscription，`needSyncData` 仍为 true。

最终结果：

- BPS 专属同步状态：成功。
- 旧 Kinetic Switch 同步状态：仍认为需要同步。
- `displayStatus` 使用 OR 条件后继续显示 `syncIssueBoundSwitch`。

## 影响范围

这个问题主要影响 UI 状态判断。BPS SAVE 成功后的数据库状态大概率已经正确：

- `pjEightKeySwitchs.syncState = synced`
- `desiredConfigHash == appliedConfigHash`
- `unbindGroupAddresses` 在成功后清空

不应通过补订阅 CCT 来消除旧 `needSyncData`，因为 BPS 业务明确不支持 CCT，且之前已修复 target model 订阅只针对亮度 Generic Level。

## 修复方案

### 推荐方案 A：BPS 状态只使用 BPS 专属 sync 判断

调整 `PJEightKeySwitchData.displayStatus`：

- 若 `proxyNode?.isBatteryPowerSwitch == true`，sync issue 只看 `needsBatteryPowerSwitchSync`。
- 非 BPS 的 8-key / Kinetic Switch 继续使用原有 `needSyncData`。

预期逻辑：

- repair 状态仍优先。
- BPS bound 状态：
  - `needsBatteryPowerSwitchSync == true` -> `syncIssueBoundSwitch`
  - 否则按 `enabled` 显示 bound enabled / bound disabled。
- 非 BPS bound 状态：
  - `needSyncData == true` -> `syncIssueBoundSwitch`
  - 否则按 `enabled` 显示 bound enabled / bound disabled。

优点：

- 修正根因，不用让 BPS 走 Kinetic Switch 的 CCT/Proxy 同步规则。
- 不影响现有 EnOcean / Kinetic Switch 的 sync issue 判断。
- 与 BPS 已有 `syncState/configVersion/hash` 设计一致。

### 备选方案 B：覆写 BPS 的 `needSyncData`

为 BPS 增加专属 `batteryPowerSwitchNeedSyncData`，或在旧 `getNeedSyncDatas()` 中识别 `proxyNode?.isBatteryPowerSwitch == true` 并改走 BPS 规则。

不推荐原因：

- `needSyncData` 当前是旧 Kinetic Switch 的公共语义，改动面更大。
- `getNeedSyncDatas(deleteSwitch:)` 还被 delete、group、node sync 等流程复用，混入 BPS 规则容易带来副作用。

## 验证计划

1. 静态检查：
   - `displayStatus` 中 BPS 分支不再 OR 旧 `needSyncData`。
   - 非 BPS 仍保留旧 `needSyncData` 判断。

2. 编译验证：
   - `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

3. 手动验证：
   - 进入 BPS Edit，修改需要同步的配置，SAVE 成功后返回 Switch 页面。
   - 再返回 Switches 页面，BPS 卡片不再显示 sync issue。
   - 修改配置但中断/失败同步后，BPS 卡片仍显示 sync issue。
   - 普通 Kinetic Switch 的未同步状态仍按原有逻辑显示。
