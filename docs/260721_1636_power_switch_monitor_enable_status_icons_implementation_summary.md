# Battery/AC Power Switch Monitor Enable 状态图实施总结

## 实施结果

- 仅调整 Battery/AC Power Switch 底部 Monitor 弹窗。
- 顶部 Enable 右侧控件由 `UISwitch` 替换为 20×20 状态图片：
  - Enable：`sensor_occupy`
  - Disable：`sensor_unoccupy`
- 展开后的 Enable/Disable 图例均改为对应的 20×20 图片。
- 顶部状态图片不绑定点击动作，并拦截自身区域触摸，确保不可操作且不会将点击穿透给弹窗展开按钮。
- 删除旧 UISwitch、触摸遮罩和自绘 Mini Switch 图例 UI。
- 保留 `enableChanged` 回调、Controller 绑定及 Battery/AC Enable/Disable 发送流程，便于未来恢复交互。

## 改动范围

- 业务代码：`PJEightKeySwitchMonitorStatusSetView.swift`
- 未修改 Controller、资源、本地化、target 配置、依赖或 NordicSigMeshSDK。

## 提交

- `ea01b8c6 fix: use icons for power switch enable status`

## 验证

- 新状态图片与 20×20 约束源码断言：通过。
- 旧 UISwitch、触摸遮罩及 Mini Switch 图例残留检查：通过，无匹配。
- Enable/Disable 发送流程保留检查：通过。
- `git diff --check`：通过。
- SunSmart Debug iPhoneOS 构建：通过，输出 `BUILD SUCCEEDED`。

## 未覆盖项

- 未连接 Battery/AC Power Switch 真机验证弹窗最终视觉与运行时状态刷新；需要在具备对应设备和数据的环境中完成验收。
