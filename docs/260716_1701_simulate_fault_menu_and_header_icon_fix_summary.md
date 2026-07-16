# Simulate Fault 菜单与标题图标修复总结

## 修复结果

- Light 设备页右上角菜单宽度由 `SCRXFrom(114)` 调整为 `SCRXFrom(140)`，为 30pt 图标、图文间距和英文 `Simulate Fault` 提供完整的单行显示空间。
- Simulate Fault 弹窗标题左侧 `black_debug` 图片视图由 16×16 调整为 30×30；其既有 30×30 容器保持不变。
- 共享 `MenuPopView`、其他页面菜单、字体、权限、弹窗内容、按钮事件和 Mesh 行为均未修改。

## 根因

菜单实例原宽度为 114pt，扣除 `MenuPopView` 的左右边距、30pt 图标和图文间距后，剩余空间不足以完整显示英文标题。弹窗标题区域虽然已有 30×30 容器，但内部图片视图被单独约束为 16×16，导致实际图片仍按 16×16 展示。

## TDD 证据

- 新增菜单宽度与标题图片尺寸契约后，首次运行 `scripts/check_simulate_fault.sh` 失败，报告 `black_debug header image must render at 30 by 30 points`。
- 独立检查确认旧代码不存在 `let menuWidth = SCRXFrom(140)`，exit code 为 1。
- 实施两处最小修改后，`scripts/check_simulate_fault.sh` 输出 `PASS: Simulate Fault contract is present.`。

## 验证结果

- `scripts/check_simulate_fault.sh`：PASS。
- `scripts/check_device_menu_icons.sh`：PASS，Light proxy 图标仍按既定要求使用 `menu_set_proxy`。
- `SimulateFaultModelTests`：PASS。
- `git diff --check`：PASS。
- iPhoneOS generic destination 构建：
  - `SunSmart`：BUILD SUCCEEDED。
  - `Archipelago`：BUILD SUCCEEDED。
  - `SLG Sync Plus`：BUILD SUCCEEDED。
  - `SylSmart`：BUILD SUCCEEDED。

## 范围检查

本次新增修复只涉及：

- `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`
- `SunSmart/Main/Device/View/SimulateFaultViewController.swift`
- `scripts/check_simulate_fault.sh`

工作区既有的 `AGENTS.md`、Site/Space key 分析文档和 Energy Data 协议分析文档未被纳入本次修改。此前的 Simulate Fault Figma 呈现改动与本次修复继续作为同一功能链保留在当前分支中。

## 待人工确认

建议在真机上展开 Light 设备右上角菜单，目视确认 `Simulate Fault` 单行完整显示；打开弹窗，确认标题左侧 `black_debug` 的视觉尺寸为 30×30，且未影响标题对齐。
