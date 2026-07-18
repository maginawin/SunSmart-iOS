# Simulate Fault 实施总结

## 实施范围

- 仅在 `DeviceLightViewController` 的右上角菜单末尾增加 `Simulate Fault`。
- 仅当当前 Space 的有效设备能力包含 `.edit` 时展示入口；弹窗展示前再次校验权限。
- 菜单图标使用 `menu_debug`，弹窗标题图标使用 `black_debug`。
- 弹窗限制在当前 light 设备页面内，与页面同宽；点击内容区外遮罩自动收起。
- 弹窗高度由内部内容及垂直约束推导。内容超过页面安全区时，仅内部滚动。

## UI 与交互

- Motion Sensor：`Normal`、`Fault`，固定标签 `Minor (3)`。
- Photocell Sensor：`Normal`、`Fault`，固定标签 `Major (2)`。
- Light Status：`Normal`、`Dim`、`Flicker`、`Dim Flicker`、`Off`，固定标签 `Critical (1)`。
- 按钮使用固定尺寸的 Collection View item，并提供瞬时按压反馈。
- item 点击后不保留选中状态、不关闭弹窗，只向 `DeviceLightViewController` 暴露类型化事件。
- 当前控制器事件处理边界不发送 Mesh 命令、不显示 HUD、不修改设备状态。

## 本地化与多 Target

- 新增 13 个 `simulate_fault_*` 功能域英文及简体中文文案。
- 新增共享的 `menu_debug` 与 `black_debug` 1x/2x/3x 图片资源。
- 新增 Swift 文件均加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target。

## 验证结果

- `scripts/check_simulate_fault.sh`：通过。
- `scripts/check_device_menu_icons.sh`：通过，light proxy 图标期望为 `menu_set_proxy`。
- `scripts/check_device_i18n_titles.sh`：通过。
- `SimulateFaultModelTests`：通过。
- Xcode 工程及英中 strings `plutil` 校验：通过。
- `git diff --check`：通过。
- iPhoneOS、Debug、关闭签名构建：
  - `SunSmart`：成功。
  - `Archipelago`：成功。
  - `SLG Sync Plus`：成功。
  - `SylSmart`：成功。

构建仍会输出项目既有的重复 asset 名、重复 Compile Sources 条目及部分 target 将 Info.plist 放入 Copy Bundle Resources 的警告；本功能未扩大范围处理这些既有问题。

## 工作区边界

以下用户原有内容未纳入本功能提交：

- `AGENTS.md` 的本地修改。
- `docs/260716_0950_site_space_network_key_analysis.md`。
- `docs/260716_1112_energy_data_mesh_protocol_analysis.md`。
