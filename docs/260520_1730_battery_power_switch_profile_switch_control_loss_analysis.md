# Battery Power Switch Profile Switch Control Loss Analysis

> 后续反馈已排除本文中“activation 短窗口误判”作为主因：实际操作中设备已真实进入 activated 状态，并且 switch configuration 命令能返回成功。本文保留作为过程记录；当前更可信的根因见 `docs/260520_1739_battery_power_switch_profile_switch_control_loss_reanalysis.md`。

## 现象

- 首次 SAVE Profile 并添加 target group 后，Battery Power Switch 基本可以控制设备。
- 后续仅切换 Profile 类型，不变更 target groups，SAVE 后 Battery Power Switch 不能控制设备。
- 现存 target groups 仍被展示在任务列表的问题已在 `260520_1718_battery_power_switch_profile_target_group_bug_analysis.md` 中分析；本文件继续分析“为什么切换 Profile 后会失去控制能力”。

## 关键协议约束

协议文档 `protocols/2422K8N_US_4DIM.md` 对已入网设备的通信窗口约束：

- 已入网后，普通按键可以发业务指令，但高交互配置必须长按 `Key2+Key7` 3 秒打开 60 秒通信窗口。
- 60 秒 combo 窗口内，APP 发 Vendor SET 才会触发续期。
- 普通按键 wake 只有约 1 秒短窗口，且不支持 config traffic 续期。
- RESET DEFAULTS 会清空所有 APP 写入的按键配置，恢复为未配置按键静默。

这意味着：只要 APP 在非 combo 60 秒窗口中发送 reset，就有机会出现“reset 已执行，后续完整 key config / publication 没下完”的状态。该状态下设备按键会静默或只残留部分能力。

## 当前激活检测问题

当前激活弹窗文案：

- Scene Profile：`Press 'Button 2' and 'Button ON' to activate the device.`
- Brightness Profile：`Press 'Button 75%' and 'Button ON' to activate the device.`

当前检测逻辑：

- 每 2 秒发送一次 `Vendor GET 0x4C 0x01`。
- 只要收到一次成功的 `batteryPowerSwitchCapability` 响应，就进入 `detected`，并开始下发 configuration。

问题在于：`GET 0x4C 0x01` 成功只能证明设备当前醒着，不能证明设备处于 Key2+Key7 长按打开的 60 秒 combo 配置窗口。

如果用户只是短按/普通按下了按钮组合，设备可能短暂醒来约 1 秒。APP 在这个短窗口内能收到 capability，于是误判为 activation detected。随后 Profile SAVE 先发送 reset，设备清空所有按键配置；但后续 Key Config 和 Model Publication 需要更长时间，短窗口不保证能完成。最终表现就是：SAVE 后设备已被 reset，但完整配置未恢复，Battery Power Switch 不能控制设备。

## 为什么首次 SAVE 更容易成功

首次添加设备后，常见情况下仍处在配网完成后的窗口或用户刚完成较长时间的激活操作，完整配置更容易在设备醒着时完成。

后续仅切换 Profile 时，流程依赖弹窗引导用户再次激活。如果文案只写 `Press`，用户很容易短按，而不是长按 Key2+Key7 3 秒。此时一次 capability GET 成功会触发误判，风险集中发生在 Profile 切换这种会发送 reset 的场景。

## 与 target group 任务列表问题的关系

现存 target groups 被错误加入任务列表不是“不能控制”的直接原因，但会放大问题：

- Profile-only SAVE 本应只配置 Battery Power Switch 自身。
- 当前错误地把现存 target groups 也加入任务列表，会增加同步耗时和失败面。
- 如果用户使用的不是 60 秒 combo 窗口，更长的任务链更容易在 reset 后出现后续配置未完成。

因此两个问题应一起修复：

- target group 任务生成改回真实差异语义。
- activation 检测不能把一次 capability 响应等同于 60 秒配置窗口。

## 可能影响的其他操作

只要流程会对 Battery Power Switch 发送 reset，然后依赖后续命令恢复完整配置，都有同类风险：

- 更新 Panel/Profile 类型。
- Scene Profile 下更新 Scene 目标。
- 更新 enabled/link group/app key 等 Battery Power Switch 自身配置。
- Sync device(s) 页面中 Configuration 失败后的 RE-Sync，因为新需求要求激活后从 reset 开始全量下发。
- 未来复用该弹窗的其他长耗时 BPS 配置功能。

以下操作风险较低：

- 仅添加 target group。
- 仅删除 target group。
- 仅组内设备订阅/取消订阅。

这些操作不应该发送 Battery Power Switch 自身 reset，也不应该要求 BPS 激活；它们只对 target devices 下发订阅调整。

## 修复方案建议

### 方案 A：增强 activation 判定，避免短 wake 误判

推荐。

1. 修改激活文案，明确要求长按组合键 3 秒：
   - Scene Profile：`Press and hold 'Button 2' and 'Button ON' for 3 seconds to activate the device.`
   - Brightness Profile：`Press and hold 'Button 75%' and 'Button ON' for 3 seconds to activate the device.`
2. 不要在第一次 capability 成功时立即进入 detected。
3. 要求至少两次连续 capability 成功，且两次成功之间间隔一个 probe 周期，例如 2 秒。
4. 只有满足连续成功条件后才进入 detected 并开始 configuration。

理由：

- 普通按键短 wake 约 1 秒，很难跨 2 秒稳定响应两次 probe。
- Key2+Key7 combo 60 秒窗口可以稳定响应多次 probe。
- 不需要新增固件协议即可显著降低误判。

代价：

- activation detected 会比当前慢约 2 秒。
- 若 BLE/Friend 质量很差，可能需要用户多等一次 probe；但比 reset 后配置不完整更可控。

### 方案 B：新增固件窗口状态确认

更彻底，但需要协议支持。

新增或扩展 capability 返回，明确告知当前是否处于 combo config window。APP 只有看到 combo window 才开始 reset/configuration。

优点是判定准确；缺点是需要固件和协议同步，不能作为当前快速修复。

## 建议与 1718 修复一起验证

1. 短按激活按钮组合时，弹窗不应立即进入 detected。
2. 长按激活按钮组合约 3 秒后，弹窗应在连续 probe 成功后进入 detected。
3. Profile-only SAVE 任务列表不包含现存 target groups。
4. Profile-only SAVE 后，BPS 仍可控制原 target groups。
5. 故意中断 reset 后的配置流程时，本地状态保持 failed，下一次 RE-Sync 仍要求 activation 并从 reset 开始完整配置。
