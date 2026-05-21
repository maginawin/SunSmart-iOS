# Battery Power Switch 电池电量展示需求分析

## 背景

截图描述的是 Battery Power Switch 在设备信息或监控页面中的电池电量、设备状态、更新时间和刷新按钮展示规则。该文档仅整理需求、合理性分析和优化建议，不包含实现方案。

## 需求整理

### 适用范围

- 本期只处理已接入 Site - Space 的真实 Battery Power Switch。
- 截图中“未关联真实设备”指虚拟设备未关联真实设备的状态，但当前暂时没有实现虚拟设备功能，因此不作为本期实现范围。
- 若未来支持虚拟设备，未关联真实设备时可按截图展示 `--` 并隐藏刷新按钮。

### 电池图标

- 展示固定的电池 icon。
- 电池 icon 不随电量变化。
- 即使低电量，icon 也保持固定样式，低电量通过电量文本和状态文本表达。

### 电池电量文本

电池电量仅在用户主动点击刷新按钮后获取。

- App 发送标准 SIG Mesh Battery Get 消息。
- 设备返回 Battery Status 后，App 保存电池电量到本地数据库。
- 保存的数据与 Site - Space 中对应的 Battery Power Switch 关联。
- 删除该 Battery Power Switch 时，同时删除关联的电池电量数据。

电量展示规则：

- 电池图标后直接展示设备上报的电池百分比，例如 `0% / 5% / 10% / 15% ... 95% / 100%`。
- App 不对设备上报的电池百分比做向上取整、向下取整或换算。
- App 不把低电量百分比替换为 `Low` 文案；低电量只影响状态展示。
- 超过 `7 days` 未更新时，电量文本仍展示最近一次成功同步后的值。
- 尚未成功刷新过电池电量时，展示 `--`。

低电量判断：

- 使用 SIG Mesh Battery Status 中的电池电量结果判断。
- 不使用额外的电压阈值规则。
- 不根据固定电压阈值在 App 侧重新换算低电量。

### 状态 Status

本期状态只包含：

- `Normal`：正常，绿色。
- `Unknown`：超过 `7 days` 未更新。
- `Low battery`：低电量，橙色。

状态优先级：

```text
IF battery_last_update_time is empty
display_state = UNKNOWN
ELSE IF now - battery_last_update_time > 7 days
display_state = UNKNOWN
ELSE IF battery <= 10%
display_state = LOW_BATTERY
ELSE
display_state = NORMAL
```

说明：

- `Unknown` 需要纳入状态判断。
- `Unknown` 表示电池数据超过 `7 days` 未刷新，不代表设备一定离线或故障。
- `Low battery` 只基于 Battery Status 的电量结果判断。

### 更新时间

更新时间表示电池电量最近一次成功刷新的时间。

需要保存：

- `battery_last_update_time`

不需要保存其他更新时间字段。

更新时间记录逻辑：

- 用户点击刷新后，只有收到设备 Battery Status 回复并成功保存电量时，才更新 `battery_last_update_time`。
- 时间使用手机当前系统时间。
- 超时、失败、用户取消时，不更新电池电量，也不更新 `battery_last_update_time`。

更新时间文本：

- `Just now`：时间差 `delta < 60s`。
- `X min ago`：时间差 `delta < 1hr`。
- `X hr ago`：时间差 `delta < 24hr`。
- `X day ago`：时间差 `delta > 24hr`。
- `--`：尚未成功刷新过电池电量，或未来虚拟设备未关联真实设备。

前端展示逻辑：

- 直接读取设备在 App 数据库中的电池电量和 `battery_last_update_time` 展示。
- 若数据库中没有该设备的电池电量数据，则视为尚未成功刷新过电池电量，电量和更新时间显示 `--`，状态显示 `Unknown`。
- UI 更新的唯一触发时机是用户主动点击刷新按钮，并且设备回复 Battery Status 后成功保存数据库。
- App 不做前端定时刷新。
- 电池电量信息只保存在 App 本地数据库，不需要同步到服务器，也不需要写入 Site / Space 同步用的 json 数据。

### 刷新按钮

展示条件：

- 已关联真实 Battery Power Switch 时展示。
- `visitor` 权限不展示。
- 未来虚拟设备未关联真实设备时不展示。

点击行为：

1. 弹窗提示用户激活设备。
2. 弹窗样式可参考 Battery Power Switch 在 Edit 页面更新 Profile 后点击 `SAVE` 的等待激活弹窗。
3. 弹窗展示期间，App 持续发送标准 SIG Mesh Battery Get 消息。
4. 发送频率为每 `3` 秒一次。
5. 若设备返回 Battery Status：
   - 停止发送 Battery Get。
   - 保存电池电量到 App 数据库。
   - 更新 `battery_last_update_time` 为手机当前时间。
   - 更新 UI 中的电量、状态和更新时间。
   - 关闭或完成弹窗。
6. 若 `60` 秒内未收到设备回复：
   - 停止发送 Battery Get。
   - 弹窗显示 timeout。
   - 弹窗支持重试。
   - 不更新电池电量。
   - 不更新 `battery_last_update_time`。

## 合理性分析

### 合理部分

- 电量只在用户主动刷新时获取，符合 Battery Power Switch 低功耗设备需要用户激活的使用方式。
- 使用标准 SIG Mesh Battery Get / Battery Status，能避免 App 自定义电压换算规则，也更符合 Mesh 模型语义。
- 若设备本身按 `5%` 档位上报，App 按设备上报值展示即可；App 侧不再做分档、取整或换算。
- `0% / 5% / 10%` 仍应展示为百分比，低电量提醒由 `Low battery` 状态承担，避免电量文本和设备上报值不一致。
- 电池 icon 固定不变可以接受，状态文本和电量文本承担主要提示职责。
- 只保留 `battery_last_update_time` 能让本期数据模型更聚焦，避免引入暂时不使用的在线时间和故障时间。
- 超过 `7 days` 时仍展示最近一次电量值合理，用户可以同时看到“旧数据值”和“数据已过期”的状态。
- 电池数据只保存在 App 本地数据库、不同步服务器合理，因为该数据由本机用户主动激活设备后刷新，暂不作为 Site / Space 配置同步数据。

### 已澄清的不完整部分

- `Unknown` 已纳入状态优先级，用于表示电池数据超过 `7 days` 未刷新或尚未成功刷新。
- `11% ~ 14%` 不再做向下取整；如果设备上报这些值，App 直接显示 `11% / 12% / 13% / 14%`。
- 电池 icon 保持固定，不随电量变化。
- Low battery 使用 SIG Mesh Battery Status 中的电池电量结果，不使用额外电压阈值。
- 只保留 `battery_last_update_time`，不保存其他更新时间字段。
- 时间使用手机当前系统时间。
- 超过 `7 days` 未更新时，电量文本继续展示最近一次成功同步后的值。
- 刷新按钮行为定义为等待用户激活并周期性发送 Battery Get，`60` 秒未回复则 timeout。
- 前端不做定时刷新，只在读取数据库或刷新成功后更新 UI。

## 建议补充的实现边界

- 数据库记录需要通过 Battery Power Switch 的唯一标识定位，唯一标识与当前所有设备使用的唯一标识保持一致。
- 删除 Battery Power Switch 时，需要同步清理其电池电量和 `battery_last_update_time` 记录，避免重新添加或切换 Space 后显示脏数据。
- 若用户在等待弹窗中退出页面或取消刷新，应停止 Battery Get 定时发送，不更新本地电量。
- 若刷新过程中收到多个 Battery Status，以第一条有效回复完成本次刷新，后续回复不重复触发 UI 完成逻辑。
- 若 SIG Mesh 返回的电量存在未知、不可用或超出合法范围的值，应保持旧值，并避免覆盖已有有效电量。
- `Unknown` 使用与 `Normal` 相同的颜色。

## 建议验收点

1. 首次进入页面且尚未刷新成功时，电量和更新时间显示 `--`，状态显示 `Unknown`。
2. 点击刷新后弹出等待激活弹窗，并每 `3` 秒发送一次标准 SIG Mesh Battery Get。
3. 设备在 `60` 秒内回复 Battery Status 后，App 保存电量和 `battery_last_update_time`，并刷新 UI。
4. 设备 `60` 秒内未回复时，弹窗显示 timeout，不更新旧电量和更新时间。
5. 电量 `0% / 5% / 10%` 直接显示百分比，状态显示 `Low battery`。
6. 电量 `11% / 12% / 13% / 14% / 15% ... 95% / 100%` 直接按设备上报值展示，App 不做取整或替换为 `Low`。
7. `battery_last_update_time` 超过 `7 days` 时，状态显示 `Unknown`，电量仍展示最近一次成功同步后的值。
8. `visitor` 权限下不展示刷新按钮。
9. 删除 Battery Power Switch 时，同时删除关联的电池电量数据。
10. 电池电量信息不同步到服务器，不写入 Site / Space 同步用 json。
11. timeout 后弹窗支持重试。
12. Battery Status 返回未知、不可用或超出合法范围的电量时，保留旧电量和旧更新时间。
