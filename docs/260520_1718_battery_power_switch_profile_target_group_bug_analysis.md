# Battery Power Switch Profile Target Group Bug Analysis

## 现象

- 添加 Battery Power Switch 后，第一次 SAVE profile 并添加 group 基本可正常控制设备。
- 之后仅更新 Profile 类型、未更新 target groups，SAVE 后现存 target groups 仍进入同步任务列表。
- 已存在 group 1，edit 添加 group 2，SAVE 时 group 1 也进入配置任务。
- 已存在 group 1 和 group 2，edit 删除 group 1，SAVE 时 group 2 也进入配置任务。
- 预期：target group 第一次加入 Battery Power Switch 的 target groups 时，已经为目标设备可控 models 订阅了 Battery Power Switch 的虚拟组；仅切换 Battery Power Switch 自身 Profile 时，不应重新调整现存 target group 的 models 订阅。

## 当前关键路径

### SAVE 前判断

- `PJPreAddEightKeySwitchesVC.submitBatteryPowerSwitch` 先计算：
  - `needsConfigurationSync`：Battery Power Switch 自身配置是否需要 reset/key config/model publication。
  - `needsTargetSync`：target devices 是否需要同步。
- `needsTargetSync` 使用 `switchData.needSyncData`。
- `DeviceSwitchData.getNeedSyncDatas` 对 Battery Power Switch target groups 使用默认的 `includeExisting = false`，理论上只有缺失订阅、需要删除订阅或存在 obsolete 订阅时才会返回 target sync。

### Sync 页面展开任务

- `SyncDevicesViewController.appendBatteryPowerSwitchItems` 在 Battery Power Switch 自身配置需要同步时，会添加 Reset、Key Config、Model Publication。
- 但它随后无条件遍历 `switchData.bindGroups`，并对每个 group 调用 `makeBatteryPowerSwitchTargetGroupModel`。
- `makeBatteryPowerSwitchTargetGroupModel` 当前对订阅任务调用 `getBatteryPowerSwitchSubscriptionMessageHandles(... includeExisting: true)`。

### helper 语义

- `getBatteryPowerSwitchSubscriptionMessageHandles(... includeExisting: false)`：
  - 只对尚未订阅 Battery Power Switch 虚拟组的目标 models 生成订阅命令。
  - 会生成 obsolete target models 的取消订阅命令，用于清理历史错误订阅。
- `includeExisting: true`：
  - 会对 Battery Power Switch 支持的 target capability models 全量生成订阅命令。
  - 即使目标设备已经正确订阅，也会返回非空 handles。

## 根因判断

根因是 Battery Power Switch 专属 Sync 页面在生成 target group 展示任务时，把“是否需要 target group 订阅同步”的判断和“强制重发”的语义混在了一起。

具体表现为：

- `appendBatteryPowerSwitchItems` 没有先按真实差异筛选 target groups。
- `makeBatteryPowerSwitchTargetGroupModel` 使用 `includeExisting: true` 作为是否创建 group task 的依据。
- 因为 `includeExisting: true` 对已正确订阅的 group 也会返回 handles，所以现存 group 会被错误加入任务列表。

这可以解释三个现象：

- 仅切换 Profile：所有现存 target groups 被重新列入任务。
- 添加 group 2：group 2 需要同步，但 group 1 因 `includeExisting: true` 也被列入任务。
- 删除 group 1：group 1 需要移除订阅，但保留的 group 2 因 `includeExisting: true` 也被列入任务。

## 对“不能控制设备”的影响推断

Profile 类型切换时，真正必须下发的是 Battery Power Switch 自身 Reset、完整 Key Config、完整 Profile Client Model Publication。target devices 的 group subscription 不应参与。

当前错误地把现存 target groups 加入任务后，可能带来以下副作用：

- 对已订阅 models 重复发送 `ConfigModelSubscriptionAdd`，增加同步耗时和失败概率。
- target device 若离线或响应慢，会把一次本应只依赖 Battery Power Switch 激活的 Profile SAVE 扩大成 target devices 同步流程。
- 如果 target group task 失败，用户会看到与实际改动无关的失败；后续本地状态还可能把 Battery Power Switch 自身配置标为已同步，从而掩盖真正需要排查的 own configuration 结果。

当前证据更支持“错误 target group 重同步导致流程被放大并引入失败风险”，而不是 target group 差异判断本身错误。

## 修复方案建议

### 方案 A：恢复 target group 差异同步语义

推荐。

1. `appendBatteryPowerSwitchItems` 中生成 target group task 时，不使用 `includeExisting: true` 判断是否需要展示任务。
2. `makeBatteryPowerSwitchTargetGroupModel` 中订阅方向改回默认差异语义：
   - 添加订阅：只生成缺失订阅和 obsolete cleanup。
   - 删除订阅：只生成实际存在的订阅删除。
3. `SyncDevicesCellModel.messageHandles` 中 `.batteryPowerSwitchTargetSubscription` 也使用默认差异语义，不强制重发已存在订阅。
4. 保留 reset 后强制完整下发 Battery Power Switch 自身配置：
   - Key Config 继续完整生成。
   - Profile Client Model Publication 继续在 reset 后使用 `includeExisting: true`。
5. 保留 Group/Profile SAVE 路径已经做过的 BPS 专属 helper 分流，避免退回传统 EnOcean Switch 订阅逻辑。

优点：

- 符合“Profile 切换不调整现存 target group 订阅”的预期。
- 新增 group 只显示新增 group。
- 删除 group 只显示被删除 group 的 unsubscription。
- 历史 obsolete 订阅仍可被清理，因为默认 helper 仍会返回 cleanup handles。
- 不影响 reset 后强制完整下发 Battery Power Switch 自身配置。

风险：

- 如果曾经依赖 target subscription 的强制重发来掩盖本地状态不准确，改回差异语义后可能暴露本地 mesh model subscription 状态不可信的问题。当前第一次添加后能控制设备，说明大多数场景本地状态应是可信的。

### 方案 B：只在 Profile-only SAVE 时跳过 target groups

不推荐。

这种做法可以解决当前表象，但会留下添加/删除 group 时现存 group 仍被错误列入任务的问题，也无法统一修正 `.batteryPowerSwitchTargetSubscription` 执行时强制重发的问题。

## 建议验证

1. 新增 Battery Power Switch，第一次添加 group 1，SAVE 后可以控制 group 1。
2. 仅切换 Profile 类型，不改 target groups，SAVE 任务列表只包含 Battery Power Switch 自身 Reset、Key Config、Model Publication，不包含 group 1。
3. 已有 group 1，新增 group 2，SAVE 任务列表只包含 group 2 的 Group Subscription，不包含 group 1。
4. 已有 group 1 和 group 2，删除 group 1，SAVE 任务列表只包含 group 1 的 Group Unsubscription，不包含 group 2。
5. 历史错误订阅过 obsolete CCT Generic Level 的设备，执行一次需要 target sync 的 BPS 同步后，obsolete subscription 能被清理。
6. reset 后仍强制发送完整 Key Config 和所有 Profile Client Model Publication。

