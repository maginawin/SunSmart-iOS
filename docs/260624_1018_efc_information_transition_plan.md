# EFC Information 进入动画问题分析与方案

## 问题

在 EFC 设备页面右上角选项菜单中选择 Information 后，进入 EFC Information 页面时体验很生硬，用户感知为没有动画。

预期：从 EFC 设备页进入 Information 页面时，应与普通设备 Information 入口一致，有自然的导航转场，不应出现菜单关闭动画与页面 push 转场互相叠加造成的突兀感。

## 代码事实

1. EFC Information 入口位于：
   `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift`

2. EFC 当前菜单项创建方式：
   - 使用 `MenuPopView.MenuItem`
   - 未设置 `hideAnimation`
   - 因此使用默认值 `hideAnimation = true`
   - 点击后先执行 `tapItemBack`，立即 `pushViewController(..., animated: true)`，随后 `MenuPopView` 再执行 0.3s dismiss fade 动画

3. `MenuPopView` 的真实点击流程：
   - `didSelectRowAt` 先调用 `item.tapItemBack?(item)`
   - 然后调用 `dismiss(animation: item.hideAnimation)`
   - 当 `hideAnimation = true` 时，菜单 fade out 会和 push 转场同时发生

4. 普通 Light / Base 设备 Information 入口已显式设置：
   `hideAnimation: false`

5. DALI 设备 Information 入口也使用：
   `hideAnimation: false`

6. Scene 的 Settings 这类会跳转新页面的菜单项也使用：
   `hideAnimation: false`

## 根因判断

问题真实存在，且 EFC 入口与同类菜单跳转入口不一致。

直接原因是 EFC Information 菜单项仍保留 `MenuPopView` 默认隐藏动画。由于 `MenuPopView` 是先执行 push，再执行菜单 dismiss，菜单 fade out 与 navigation push 同时叠加，视觉上容易显得卡顿、生硬或像没有正常页面转场。

这不是 `DeviceInformationViewController` 本身缺少动画。该页面在普通设备入口中同样通过 `navigationController?.pushViewController(..., animated: true)` 进入，关键差异是普通入口关闭了菜单隐藏动画。

## 方案对比

### 方案 A：只对 EFC Information 菜单项设置 `hideAnimation: false`（推荐）

做法：

- 在 `makeInformationMenuItem()` 中把 EFC Information 的 `MenuPopView.MenuItem` 改成显式 `hideAnimation: false`
- 保留现有 `pushViewController(..., animated: true)`
- 不改 `MenuPopView` 通用组件
- 不改 `DeviceInformationViewController`

优点：

- 与 Light / Base / DALI 的 Information 入口保持一致
- 改动最小，影响面只限 EFC Information 菜单项
- 不改变 Delete / Refresh / Edit 等其他菜单项的关闭动画
- 容易用 contract 脚本守住

风险：

- 如果用户期望的是自定义转场效果，而不是恢复普通导航 push 体验，此方案只会做到“与现有设备页一致”，不会新增特殊动画。

### 方案 B：改 `MenuPopView`，让所有菜单项先 dismiss 再执行 action

做法：

- 调整 `MenuPopView.didSelectRowAt`
- 让 `hideAnimation = true` 时先执行 dismiss completion，再执行 action

优点：

- 从组件层面解决 action 与 dismiss 动画重叠的问题

风险：

- 影响所有使用 `MenuPopView` 的页面
- Delete / Refresh / Identify 等操作的点击反馈时序会改变
- 需要更大范围回归，超出当前 EFC Information 问题范围

### 方案 C：为 EFC Information 单独做自定义转场

做法：

- 保留菜单默认 dismiss
- 新增自定义 transition 或延迟 push

优点：

- 可以做出独立视觉风格

风险：

- 与项目现有设备详情入口不一致
- 为单个页面引入过重机制
- 容易产生手势返回、导航栏状态、modal root 场景的额外边界问题

## 推荐方案

推荐使用方案 A。

具体修改：

- 文件：`SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift`
- 方法：`makeInformationMenuItem()`
- 把 Information 菜单项改为：
  - `hideAnimation: false`
  - 保持原有 push 逻辑不变
  - 保持前一次修复的 `nameOverride` 不变

## 验证计划

1. 静态 contract：
   - 在 `scripts/check_efc_controller_flows.sh` 中增加断言，要求 EFC Information 菜单项包含 `hideAnimation: false`
   - 避免未来回退成默认隐藏动画

2. 代码检查：
   - 确认只改 EFC Information 菜单项
   - 确认 Edit / Delete / Refresh / Visitor Information 仍走同一个 `makeInformationMenuItem()`

3. 构建验证：
   - 运行：
     `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

4. 手工验证：
   - 进入 EFC 设备页面
   - 打开右上角菜单
   - 点击 Information
   - 确认菜单不再先 fade 叠加页面 push，页面进入动画与普通 Light / Base Information 一致
   - 退回 EFC 页面，确认返回动画正常

## 待确认

是否按方案 A 执行：仅给 EFC Information 菜单项补 `hideAnimation: false`，并补 contract 检查。
