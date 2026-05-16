# Space Debug 菜单图标优化设计

## 背景

当前 Site / Space 页面右上角菜单中的 `Debug` 入口使用 `menu_information` 图标。该图标是信息 `i` 样式，更适合信息页，不够符合调试、诊断入口的含义。

Debug 菜单项位于 `SpaceViewController.moreClick()` 中，当前代码使用：

```text
icon: UIImage(named: "menu_information")
title: "debug".localizedString
```

## 目标

- 将 Site / Space 右上角菜单中 `Debug` 菜单项的图标换成更符合调试含义的图标。
- 复用现有资源，避免新增 asset 和 target 配置改动。
- 不改变 Debug 菜单项的展示位置、文案、权限判断和点击行为。

## 确认方案

使用现有资源 `menu_profile_test` 作为 Debug 图标。

选择原因：

- `menu_profile_test` 是小窗口内 `</>` 的视觉，更接近调试、诊断、开发工具入口。
- 已包含 `@2x` 和 `@3x` 图片资源，尺寸与当前菜单图标体系一致。
- 只需要替换 `UIImage(named:)` 的资源名，改动范围最小。

## 非目标

- 不新增新的图标资源。
- 不修改 `Debug` 文案和本地化。
- 不修改右上角菜单布局。
- 不修改 Debug 页面的入口权限。
- 不修改 `MenuPopView` 组件。

## 设计细节

在 `SunSmart/Main/Space/Controller/SpaceViewController.swift` 中，将 Debug 菜单项的图标从：

```text
menu_information
```

替换为：

```text
menu_profile_test
```

其他菜单项保持不变。

## 验证计划

- 静态检查 `Debug` 菜单项使用 `UIImage(named: "menu_profile_test")`。
- 静态检查 `menu_information` 仍可被其他信息入口继续使用，不做资源删除。
- 构建 `SunSmart` Debug iOS target，确认无编译错误。
- 真机或模拟器打开 Site / Space 右上角菜单，确认 `Debug` 图标显示为 `</>` 样式，点击后仍进入 Debug 页面。
