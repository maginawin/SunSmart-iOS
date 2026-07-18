# Simulate Fault View Controller 改造总结

## 结果

- `SimulateFaultOverlayView` 已替换为 `SimulateFaultViewController`。
- 新 View Controller 明确使用 `.automatic` 和标准 `present(animated: true)`。
- UIKit 管理弹窗宽度、高度、圆角、半透明背景和交互式下滑关闭。
- 已移除 overlay 的 outside-tap policy、自定义 dismiss 动画和对底层 interactive-pop 手势的状态修改。
- 系统 dimming 区域不安装自定义点击手势；不再要求点击弹窗外关闭。
- Motion Sensor、Photocell Sensor、Light Status 的固定内容、Collection View 换行和 item 高亮效果保持现状。
- Section item 产生的 `SimulateFaultAction` 在新 VC 的 `handleAction` 中终止，不向其他控制器回传。
- 点击 item 不关闭弹窗、不保留选中状态、不发送 Mesh 命令。
- 新 VC 独立监听 Space 权限变化，丢失 effective edit capability 时主动 dismiss。
- 新 View Controller 文件仍同时属于 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 target。

## TDD 证据

- 修改 contract 后首次运行失败：`FAIL: SimulateFaultViewController.swift is missing`。
- 实现后 `scripts/check_simulate_fault.sh` 输出 `PASS: Simulate Fault contract is present.`。
- `SimulateFaultModelTests` 保留 9 个 typed action 和 Collection View grid metrics 回归，输出 `SimulateFaultModelTests passed`。
- 已删除不再属于纯 `.automatic` 方案的 `SimulateFaultDismissalPolicy` 及对应测试。

## 定向验证

- Simulate Fault contract：PASS。
- Device menu icon contract：PASS，`check_device_menu_icons.sh` 仍按既定要求检查 `menu_set_proxy`。
- Device i18n title contract：PASS。
- `SunSmart.xcodeproj/project.pbxproj`、English 和简体中文 `Localizable.strings` 的 `plutil -lint`：OK。
- `git diff --check`：无错误。

## iPhoneOS Debug 构建

- SunSmart：`BUILD SUCCEEDED`。
- Archipelago：`BUILD SUCCEEDED`。
- SLG Sync Plus：`BUILD SUCCEEDED`。
- SylSmart：`BUILD SUCCEEDED`。

构建使用 `generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`，未使用 Simulator。构建日志中的 asset symbol 重名、旧 API、Info.plist resource 和 duplicate build file 警告为工程既有警告，本次未扩大范围处理。

## 人工验收清单

- 从 Lights 列表 modal 设备页和 Group push 设备页分别打开 Simulate Fault。
- 确认弹窗使用当前系统的 `.automatic` modal/sheet 样式与半透明背景。
- 确认可通过系统下滑手势关闭。
- 确认内容超过可用高度时可滚动访问全部 item。
- 确认 item 点击不关闭弹窗、不保留选中状态、不触发 Mesh 命令。
- 确认关闭 Simulate Fault 后，底层 Device Light 的 push 侧滑或 modal 下滑保持系统原生行为。
