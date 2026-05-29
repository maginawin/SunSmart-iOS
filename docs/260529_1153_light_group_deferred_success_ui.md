# Light Group Deferred Success UI 调查记录

## 背景

添加 light 设备并直接加入 group 后，功能同步正常，但 UI 上设备已显示成功时，导航栏返回按钮仍会延迟出现，给人感觉像 UI 卡住。

## 根因

父级 `DeviceAddViewController` 通过子控制器的 `deviceStateCallback(false)` 恢复返回按钮和交互。上一版 deferred group sync 已经把该回调放在 `finishGroupDeferredSyncPlans` 完成之后，因此返回按钮延后是符合当前数据流的。

真正不一致的是设备行状态：Classic 和 Professional 的 `addSuccess` 闭包会立即把 `ProvisioningDevice.addState` 设为 `.success` 并刷新列表；但此时 deferred group sync 还没有完成。用户看到“添加成功”后返回按钮仍不可见，就会误以为 UI 卡住。

## 修复策略

- 只对存在 deferred group sync 的 light + group 添加流程延迟展示成功状态。
- `addSuccess` 阶段仍记录成功 node、restoreData、BPS 后续请求和 deferred plan。
- 若该设备有 deferred tasks，则把对应 `ProvisioningDevice` 放入 pending 列表，暂不设置 `.success`。
- `finishGroupDeferredSyncPlans` 完成后，无论 deferred 成功或失败，都把 pending 设备统一设为 `.success` 并刷新 UI。
- deferred 失败仍只负责标记 group 待同步，不影响最终添加成功展示。
- 没有 deferred tasks 的设备保持原有即时 `.success` 行为。

## 验证重点

- light + group 且有 group 关联功能时，设备行应在 deferred 命令结束后才显示 success。
- deferred 成功或失败后，最终都显示添加成功。
- 返回按钮与成功状态应同步出现，不再出现“已成功但无法返回”的中间状态。
- 非 light、light 不入组、无 deferred tasks 的行为保持原样。
