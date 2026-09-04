# Space Main Search by Name 按钮迁移实施总结

## 1. 实施结果

Space Main 的 Search by Name 入口已从左下角设备数量控件迁移到独立的纯图片按钮，Search、Reset、共享过滤条件和列表过滤逻辑保持不变。

完成后的行为：

- 左下角设备数量控件固定使用 `space_device_count`，继续显示原始设备数量/容量，不再响应点击，也不再随过滤状态换图。
- 新按钮正常状态使用 `device_filter`，过滤生效时使用 `device_filter_selected`，视觉尺寸为 30×30。
- Lights 中新按钮位于 `space_sort` 左侧；需要显示 `sync_failed` 时，Sync 位于新按钮左侧。
- Switches、Sensors、Others 中新按钮位于 `share_delete` 左侧。
- Search by Name / Reset 菜单改为锚定新按钮，因此显示在新按钮上方。
- 编辑状态隐藏新按钮，退出编辑状态后只在已配置的 Main 分类恢复。
- Group、Scene、Timed、Gateway、EFC 等共享 Footer 使用方没有启用新按钮。

## 2. 改动范围

### 2.1 共享 Footer

修改 `SunSmart/Main/Space/View/SpaceFunctionFooterView.swift`：

- 新增可配置的独立过滤按钮。
- 新增 Lights 与其他 Main 分类两种相对布局。
- 过滤激活状态改为驱动新按钮的 selected 状态。
- 设备数量控件恢复为静态展示语义。
- 编辑态显隐逻辑纳入新按钮。

### 2.2 Main 四分类

修改：

- `DeviceLightsViewController.swift`
- `DeviceSwitchesViewController.swift`
- `DeviceSensorsViewController.swift`
- `DeviceOthersViewController.swift`

四个控制器分别配置所需的按钮位置，并把菜单锚点从 `countBtn` 改为 `deviceFilterBtn`。既有过滤会话、完整数据与可见数据分离、空结果状态、选择、同步和 Reset 逻辑没有调整。

### 2.3 测试

新增 `Tests/Device/SpaceMainDeviceFilterFooterContractTests.swift`，覆盖：

- 数量控件不再作为过滤入口；
- normal / selected 图片和 30×30 尺寸；
- Lights 的 Sort、Filter、Sync 顺序；
- 其他分类的 Edit、Filter 顺序；
- 四分类菜单使用新按钮作为锚点；
- 编辑态显隐；
- 非 Main Footer 使用方默认不受影响。

本次没有新增或修改资源、本地化、target 配置、依赖或 NordicSigMeshSDK。

## 3. 验证结果

以下自动化测试通过：

- `DeviceNameFilterSessionTests`
- `DeviceNameFilterMenuViewContractTests`
- `DeviceNameFilterSearchViewContractTests`
- `DeviceNameFilterExpansionContractTests`
- `SpaceMainDeviceFilterFooterContractTests`
- `git diff --check`

以下 generic iPhoneOS、Debug、关闭签名构建通过：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart
- Lumineux

构建日志仍包含工程既有警告：部分品牌 target 把 Info.plist 放入 Copy Bundle Resources，以及部分 FSCalendar 源文件重复进入 Compile Sources。本次改动没有新增这些警告。

## 4. 未完成的实际 UI 验收

尝试通过 CoreDevice 查询连接设备时，`CoreDeviceService` 初始化超时，当前无法执行真机安装与布局检查。因此以下项目仍需在实际 iPhone 与 iPad 上验收：

- Lights 有/无 `sync_failed` 时的按钮间距、垂直对齐和点击区域；
- Switches、Sensors、Others 的 Filter 与 `share_delete` 相对位置；
- `space_sort` 显示/隐藏两种状态下的实际布局；
- 菜单是否稳定显示在新按钮上方且不越过安全区；
- 编辑态、分类切换、Search、Cancel、Reset 和 selected 图片切换的完整交互。

自动化契约和五 target 构建只能证明源码关系与编译集成，不能替代上述真机 UI 验收。
