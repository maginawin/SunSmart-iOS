# WiFi Gateway Activate Section 调整计划

## 背景

Figma 节点 `193:2418` 中，`Activate` 是一个独立的白色圆角列表 section：左侧标题为 `Activate`，右侧为开关控件。当前 `GatewayViewController` 中的 `Activate` 行位于基本信息 section 末尾，不在 `Name` 下方。

## 已确认方案

- 在 `Name` section 下方新增独立 table view section：`Activate`。
- 新 section 复用现有 `CustomTableViewCell` 的 `.switch` 样式，保持 44pt 行高、白色圆角卡片和当前开关视觉。
- 开关状态与交互遵循当前做法：
  - 使用 `setGatewayModel.activate` 作为当前显示状态。
  - 点击时继续执行连接中、编辑权限、网关未授权校验。
  - 校验通过后更新 `setGatewayModel.activate` 并刷新 Save 按钮状态。
- 从基本信息 section 删除旧的 `Activate` 行。

## 非目标

- 不新增“默认禁用”行为。
- 不修改 `CustomTableViewCell` 通用样式，避免影响其它页面。
- 不改网关保存、同步、授权、删除、APN 或关联 Space 行为。
- 不新增或修改本地化 key，继续复用现有 `"activate".localizedString`。

## 验证

- 静态检查：`git diff --check`
- 构建验证：
  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
