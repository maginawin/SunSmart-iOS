# Group Daylight AUTO 状态一致性分析

## 结论

`Daylight harvesting (Closed loop)` 页面中 Sensor 行的 `group_auto` 有可能与设备实际状态短暂或长期不一致，但主要风险不是“切换传感器后错误显示旧传感器的 AUTO On”，而是“实际 AUTO On，但 UI 未显示”。

针对“从 group 页右上角 calibrate 进入 calibration，选择其他传感器并重新校准，再返回 group 页”的场景：

1. 成功切换或校准新 daylight sensor 后，`LightSensorCalibrationViewController` 会把 `group.info.ambientLightSensorNodeAddress` 更新为新传感器地址。
2. 返回 group 页触发 `GroupViewController.viewWillAppear()`。
3. `updateUI()` 会先刷新 Sensor 行，并在 `.daylight` profile 设置 `supportSensorType = .ambientLight`。这个 setter 会先执行 `controlStateImageView.isHidden = true`，所以旧传感器的 `lightControlOn == true` 不会稳定残留显示。
4. 随后 `refreshAutoState()` 针对当前 `group.info.ambientLightSensorNode` 发送 `LightLCLightOnOffGet()`。
5. 只有收到当前绑定传感器的 `LightLCLightOnOffStatus(isOn: true)` 后，`updataSensorAutoStateUI()` 才会重新显示 `group_auto`。

因此，按现有代码，切换到新传感器后更可能出现的是：

- 查询响应回来前，`group_auto` 暂时隐藏。
- 如果 `LightLCLightOnOffGet()` 没有响应、响应丢失、代理切换期间消息未被 group 页处理，`group_auto` 会继续隐藏，即使设备实际已被 `restoreGroupAutoAfterDaylightCalibration()` 设置为 Auto On。

## 不太会发生的情况

“旧传感器的 AUTO On 状态直接导致新传感器页面显示 A”不太符合当前代码路径，原因是：

- `GroupSensorView.sensors` 确实可能在局部刷新时读取某个光照传感器的 `lightControlOn`。
- 但 `GroupViewController.updateUI()` 随后设置 `.daylight` 的 `supportSensorType = .ambientLight`，会先隐藏 `controlStateImageView`。
- 最终是否显示由 `GroupViewController.updataSensorAutoStateUI()` 决定，而它读取的是 `group.info.ambientLightSensorNode?.lightControlOn`，也就是当前绑定的 daylight sensor。

## 代码依据

- `SunSmart/Main/Group/Controller/GroupViewController.swift`
  - `viewWillAppear()`：先 `updateUI()`，再 `refreshAutoState()`。
  - `refreshAutoState()`：对当前 `group.info.ambientLightSensorNode.lightLCModel` 发送 `LightLCLightOnOffGet()`。
  - `didReceiveMessage`：收到 `LightLCLightOnOffStatus` 后写入 `sensorNode.lightControlOn`，再调用 `updataSensorAutoStateUI()`。
  - `updataSensorAutoStateUI()`：只有 `.daylight` profile 会按当前绑定 sensor 的 `lightControlOn` 显示 A；其他 profile 强制隐藏。

- `SunSmart/Main/Group/View/GroupSensorView.swift`
  - `controlStateImageView` 使用 `group_auto`。
  - `supportSensorType.didSet` 先把 `controlStateImageView.isHidden = true`。

- `SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift`
  - 校准成功后 `sensorEnabled(sensor:)` 成功才更新 `group.info.ambientLightSensorNodeAddress`。
  - `restoreGroupAutoAfterDaylightCalibration()` 会发送 `LightLCLightOnOffSetUnacknowledged(true)`，但这是 unack 消息，本身不会更新 UI 的 `lightControlOn` 缓存。

## 风险点

当前 UI 的 A 状态依赖异步查询结果，而不是在 calibration 恢复 Auto 成功后直接更新本地状态。由于恢复 Auto 使用 unack 消息，App 没有收到确定回包时不会立即知道真实状态。

所以存在这些不一致：

1. `restoreGroupAutoAfterDaylightCalibration()` 已发送 Auto On，但回到 group 页的 `LightLCLightOnOffGet()` 超时或丢失，UI 不显示 A。
2. 新传感器实际 Auto On，但本地 `newSensor.lightControlOn` 仍是默认 `false`，直到收到 `LightLCLightOnOffStatus` 前都隐藏 A。
3. 如果设备实际执行 Auto On 失败，但后续查询返回旧状态或无响应，UI 也只能表现为查询结果或隐藏，无法证明恢复命令成功。

## 建议

如果要让 UI 更符合用户预期，建议在成功切换或校准新 daylight sensor，并且调用 `restoreGroupAutoAfterDaylightCalibration()` 后，回到 group 页时显示“查询中”或明确等待 `LightLCLightOnOffStatus`；不要把默认 hidden 当作真实 Off。

如果希望立即乐观显示，也应该只对当前 `group.info.ambientLightSensorNode` 设置本地 `lightControlOn = true`，并在随后查询失败或返回 false 时回滚。
