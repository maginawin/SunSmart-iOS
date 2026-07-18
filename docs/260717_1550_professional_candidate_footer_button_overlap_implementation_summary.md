# Professional Mode Candidate Footer Button Overlap Implementation Summary

## 结果

已按方案 A 完成修复：Professional Mode 的 Candidate Device List 在查找设备时，由同一个 footer 状态入口隐藏 `Add Selected` 并显示 revoke；暂停或停止查找时按原有语义切换回来，不再出现两个按钮同时显示和覆盖。

## 修改内容

### Candidate view

修改 `SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift`：

- 增加唯一的“正在查找设备”判断，保持原有 scanning、refresh 和 light sensing 组合语义。
- 把 revoke 的 hidden/enabled、批量选择控件隐藏和 `Add Selected` hidden 集中到 `updateFooterViewState()`。
- `updateUIState()` 不再直接写 footer 按钮状态，而是在完成通用 UI 更新后调用唯一 footer 渲染入口。
- 保留 candidateDevices 更新后再次刷新 footer 的行为，确保设备分类与选中数量使用最新 `showDevices`。
- 未修改 `DeviceAddBottomView`、Professional controller、Classic Mode 或虚拟目标添加规则。

### 回归闸门

新增 `scripts/check_professional_candidate_footer_visibility.sh`：

- 校验查找状态只有一个判断来源。
- 校验通用 UI 刷新不再直接改写 footer hidden 状态。
- 校验所有通用 UI 刷新最终进入统一 footer 渲染。
- 校验 `Add Selected` 与 revoke 的互斥条件。

## TDD 证据

第一轮 RED：生产代码修改前，回归闸门因缺少统一查找状态、通用 UI 与 footer 双写、缺少互斥公式而失败。

第一轮 GREEN：集中 footer 状态后，回归闸门通过。

第二轮 RED：提交前自检发现部分设备状态入口只调用 `updateUIState()`，新增“通用 UI 刷新必须进入统一 footer 渲染”要求后，检查按预期失败。

第二轮 GREEN：让 `updateUIState()` 统一调用 footer 渲染入口并移除冗余调用后，检查再次通过。

## 验证结果

- `scripts/check_professional_candidate_footer_visibility.sh`：PASS。
- `bash scripts/check_efc_controller_flows.sh`：PASS。
- `git diff --check`：PASS。
- iPhoneOS `SunSmart` Debug build，关闭代码签名：`BUILD SUCCEEDED`。

构建过程中仍有工程既有的 asset symbol 重名及旧 API warning，本次修改文件没有新增 warning。

## 影响面

- 修改的是四个品牌 target 共用的 Swift 源文件，但没有 target 条件分支、资源或配置变化。
- 主要修复 iPhone Candidate Device List 底部弹窗；iPad 嵌入式 Candidate view 共享同一状态逻辑，也不会再同时显示两个按钮。
- 虚拟目标下 `Add Selected` 继续保持隐藏；查找中仍可显示 revoke，停止后两个右侧操作均隐藏，符合原有单设备添加限制。

## 仍需交互验收

构建和静态状态矩阵已验证。建议真机在 `Site > Space > Add Device > Professional Mode > Candidate Device List` 走一遍开始、暂停、恢复、停止查找，确认视觉切换与产品预期一致。
