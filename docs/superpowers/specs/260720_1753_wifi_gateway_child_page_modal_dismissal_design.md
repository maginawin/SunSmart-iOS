# WiFi/4G Gateway 子页面下滑关闭保护设计

## 背景

WiFi Gateway 与 4G Gateway 的详情页由 `WiFiGatewayViewController` 承载，并作为 `NavigationViewController` 的根页面以模态方式展示。当前从右上角菜单进入 `WiFi DFU` 或 `Information` 后，用户仍可下滑关闭外层模态导航控制器，导致整个 View Controller 栈被关闭。

## 目标

- 进入 `WiFi DFU` 或 `Information` 后，禁止通过下滑手势关闭整个模态导航栈。
- 从上述页面返回 WiFi/4G Gateway 主页面后，恢复原有下滑关闭能力。
- 保护状态需要覆盖从 `WiFi DFU` 或 `Information` 继续进入的子页面，直到返回 Gateway 主页面。
- 不改变其他设备的 `Information` 页面，也不改变 Gateway 主页面原有的下滑关闭行为。

## 方案

改动限定在 `WiFiGatewayViewController`：

1. 两个菜单入口在 push 目标页面前，将外层 `navigationController.isModalInPresentation` 设置为 `true`。
2. 同时记录本次需要在返回 Gateway 主页面后恢复模态关闭状态。
3. Gateway 主页面重新完成显示时，在 `viewDidAppear` 中恢复进入子页面前的 `isModalInPresentation` 原值，并清除待恢复状态。

选择 `viewDidAppear` 而不是 `viewWillAppear` 恢复，是为了避免交互式返回手势开始但随后取消时过早解除保护。保护设置在外层导航控制器上，因此目标页面继续 push History 等子页面时，整个模态栈仍保持不可下滑关闭。

## 状态边界

- Gateway 主页面首次显示：不修改外层导航控制器现有状态。
- 点击 `WiFi DFU`：保存原值并启用保护，然后 push `WiFiFirmwareUpdateViewController`。
- 点击 `Information`：保存原值并启用保护，然后 push Gateway 专用配置的 `DeviceInformationViewController`。
- 目标页面或其后续子页面显示期间：保持保护。
- 完整返回 Gateway 主页面并触发 `viewDidAppear`：恢复保存的原值。
- 其他菜单入口：保持现状。

## 实现约束

- 不修改共享的 `DeviceInformationViewController`。
- 不修改 `NavigationViewController` 的全局行为。
- 不改变 WiFi DFU、Information、History 页面现有业务逻辑。
- 不新增用户可见文案、本地化资源、依赖或 target 配置。

## 验证

1. 增加聚焦 shell contract，验证：
   - `WiFi DFU` 和 `Information` 两个入口均通过同一保护入口执行 push。
   - 保护作用于外层 `navigationController.isModalInPresentation`。
   - 仅在 Gateway 主页面 `viewDidAppear` 后恢复原值。
2. 运行聚焦 contract。
3. 运行 `git diff --check`。
4. 使用 iPhoneOS generic destination、关闭代码签名，分别构建：
   - `SunSmart`
   - `Archipelago`
   - `SLG Sync Plus`
   - `SylSmart`

## 验收标准

- WiFi Gateway 与 4G Gateway 进入 `WiFi DFU` 后，不能下滑关闭整个页面栈。
- WiFi Gateway 与 4G Gateway 进入 `Information` 后，不能下滑关闭整个页面栈。
- 从上述页面返回 Gateway 主页面后，可以继续按原行为下滑关闭。
- 其他设备与其他 Gateway 菜单入口行为不变。
