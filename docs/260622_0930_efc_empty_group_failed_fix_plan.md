# EFC Empty Group Failed Toast Fix Plan

## 背景

测试路径：新建空 Group，将 EFC 设备关联到该 Group 后，在 EFC 监控页点击 Group 图标。

当前行为真实存在：EFC 监控页会展示该关联 Group，但点击时 `toggleAssociatedGroup(_:)` 检查到 Group 内没有在线有效节点后，直接显示通用 `Failed` toast。

## 采用方案

采用方案 C：保留“不执行空组控制、不发送 Mesh 命令”的现有保护，只把通用失败提示改成明确原因提示。

## 修改范围

- `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift`
  - 将空组或无有效节点时的 `failed !` toast 改成明确的 `Not executed. No devices in this group.`
  - 保留权限、紧急状态、Mesh 发送逻辑不变。
- `scripts/check_efc_controller_flows.sh`
  - 增加 contract，防止 EFC 组点击的空组提示退回通用 `failed !`。

## 验证计划

1. 先运行 EFC contract，确认新增 contract 在实现前失败。
2. 修改 EFC 监控页 toast。
3. 重新运行 EFC contract，确认通过。
4. 运行 iPhoneOS `xcodebuild` 编译验证。
