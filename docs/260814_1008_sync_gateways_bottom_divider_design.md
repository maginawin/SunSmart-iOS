# Sync Gateways 底部淡蓝分隔线移除设计

## 问题与根因

`SyncGatewaysViewController` 的 `scrollView` 底部直接连接 `bottomActionBar` 顶部。淡蓝色线条不是约束间隙，也不是滚动视图边框，而是 `SyncGatewaysBottomActionBar` 在初始化时显式创建的顶部 `divider`：颜色为 `RGB(193, 207, 226)`，高度为 `0.5pt`。

## 已确认方案

采用方案 A：删除 `divider` 的创建、颜色设置、视图添加和约束。保留 `bottomActionBar` 的白色背景、Done 按钮尺寸、整体高度和安全区布局。

## 改动范围

- 修改 `SunSmart/Main/Site/View/SyncGatewaysSupportingViews.swift`。
- 在现有 `Tests/Site/SyncGatewaysUIContractTests.swift` 中增加源码契约，确保底部操作栏不再创建该分隔线。
- 不修改 `SyncGatewaysViewController` 的滚动区域约束，不调整本地化、资源、target 配置或依赖。

## 验证

1. 先运行新增契约并确认其在生产代码修改前失败。
2. 删除分隔线后再次运行契约并确认通过。
3. 运行 `git diff --check`。
4. 使用 generic iPhoneOS destination 构建 `SunSmart` target，且关闭代码签名。

## 验收标准

- `scrollView` 与 `bottomActionBar` 交界处不再出现淡蓝色线条。
- Done 按钮及底部操作栏原有尺寸和交互保持不变。
