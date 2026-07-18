# Professional Mode Candidate Footer Button Overlap Implementation Plan

> **执行方式：** 按用户项目约束使用 `superpowers:executing-plans` 在当前会话 Inline Execution，不使用 subagents。

**目标：** 修复 Professional Mode Candidate Device List 查找设备时 `Add Selected` 与 revoke 按钮同时显示并互相覆盖的问题，同时保留虚拟目标批量选择限制。

**架构：** 不改变 controller、共享 footer 或 Add Device 业务流程。只在 `DeviceAddCandidateDeviceListView` 内把“是否正在查找设备”和“是否隐藏批量选择控件”合并为唯一 footer 渲染逻辑，消除多个函数对同一隐藏状态的竞争写入。

**技术栈：** Swift、UIKit、SnapKit、现有 shell 回归检查、Xcode iPhoneOS build。

## 全局约束

- 只修改 Candidate footer 状态及其回归检查，不重构无关 Add Device 逻辑。
- 不新增或修改用户可见文案、本地化、资源、target 配置、依赖、SDK 或 Auth 信息。
- 保持 manual、RSSI range、motion sensing、light sensing 的现有查找状态语义。
- 保持 Battery/AC Power Switch、Emergency Controller、Dongle 等虚拟目标的批量选择隐藏规则。
- 主要验收路径为 iPhone 底部 Candidate Device List；同时保证共享 iPad view 状态一致。

---

### Task 1：建立 Candidate footer 可见性回归闸门

**文件：**

- 新增：`scripts/check_professional_candidate_footer_visibility.sh`
- 检查：`SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift`

- [ ] 新增聚焦的 source regression check，要求查找状态有唯一判断，并要求 footer 刷新同时决定 `Add Selected` 与 revoke 的互斥显示。
- [ ] 在生产代码修改前运行检查，确认因缺少统一状态判断而失败，形成 RED 证据。

### Task 2：集中 Candidate footer 状态渲染

**文件：**

- 修改：`SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift`

- [ ] 增加唯一的“正在查找设备”判断，沿用当前 `state`、`isRefresh`、`lightSeningMode` 语义。
- [ ] 将 revoke 的 hidden/enabled、批量选择控件隐藏和 `Add Selected` hidden 统一移动到 footer 状态刷新入口。
- [ ] 从通用 UI 刷新函数移除 footer 按钮可见性的重复写入。
- [ ] 运行回归检查，确认 GREEN。

### Task 3：验证并交付

**文件：**

- 新增：`docs/260717_1550_professional_candidate_footer_button_overlap_implementation_summary.md`

- [ ] 运行 `scripts/check_professional_candidate_footer_visibility.sh`。
- [ ] 运行仓库已有相关 Add Device/EFC 静态回归检查，确认虚拟目标共享流程未被破坏。
- [ ] 运行 `git diff --check` 并审查目标文件 diff。
- [ ] 按项目规则直接运行 iPhoneOS `xcodebuild` 验证 `SunSmart`。
- [ ] 保存实施总结，记录修改范围、验证证据和仍需真机确认的视觉路径。
- [ ] 仅提交本任务的 Swift、回归检查和文档文件，commit message 不包含 Codex 说明。

## 验收矩阵

| 状态 | Add Selected | Revoke |
| --- | --- | --- |
| 普通目标，正在查找 | 隐藏 | 显示 |
| 普通目标，暂停/停止 | 显示 | 隐藏 |
| 虚拟目标，正在查找 | 隐藏 | 显示 |
| 虚拟目标，暂停/停止 | 隐藏 | 隐藏 |

额外要求：任何状态下两个右侧按钮都不能同时显示；Select All 左侧控件继续只由批量选择限制控制。
