# 4G Gateway 页面优化实施计划

> **执行方式：** 使用 `superpowers:executing-plans` 在当前 `time-zone` linked worktree Inline Execution；不使用 subagents。

**目标：** 让所有非 WiFi Gateway 使用与 WiFi Gateway 对齐的导航、菜单、Information、Identify 和底部布局，同时仅保留 DFU 差异。

**架构：** 新增 Foundation-only 的 Gateway 菜单策略作为菜单顺序和底部模式的单一事实源；`GatewayViewController` 承担共同 UI、副作用和模态保护；`WiFiGatewayViewController` 只覆盖 WiFi DFU 与既有网络配置能力。

**技术栈：** Swift、UIKit、SnapKit、现有 Gateway 控制器、Swift standalone tests、Bash contracts、Xcode generic iPhoneOS build。

## 全局约束

- 不新增或修改任何 Auth 信息。
- 不新增 `0x2703` PID 配置或 UI 特判。
- 不修改 NordicSigMeshSDK。
- 用户可见文案必须同步 English 与简体中文。
- 不改变 Delete、Associated Spaces、APN、Server Information、SAVE、修复和同步协议语义。
- 不格式化无关文件，不覆盖现有未跟踪文档。
- 直接运行 `xcodebuild`，不使用 shell 包装、日志重定向或 Simulator。
- 修改共享 Sources、本地化和 project 配置后，验证 SunSmart、Archipelago、SLG Sync Plus、SylSmart。
- 不 commit、不 push。

---

### Task 1：用失败测试固定 Gateway 菜单与底部策略

**文件：**

- Create: `SunSmart/Main/Device/Gateway/Model/GatewayMenuPolicy.swift`
- Create: `Tests/Device/GatewayMenuPolicyTests.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

**接口：**

- 输入：Gateway DFU 类型、是否允许 Delete、Gateway 是否配置完成。
- 输出：有序菜单 Action 数组、Bottom Action Mode。
- 不依赖 UIKit、Node、Site、Gateway、数据库、网络或 Mesh。

**步骤：**

1. 先创建纯 Swift 测试，使用手工期望数组覆盖 4G/WiFi、Delete 有无、Configured/Repair 四类决策。
2. 在生产策略文件不存在时运行 standalone 编译，确认 RED 原因是缺少生产策略，而非测试语法错误。
3. 创建最小策略实现并加入四个品牌 target 的 Sources。
4. 重新编译运行 standalone 测试，确认 GREEN。
5. 做 mutation check：确认替换 4G/WiFi 第一项、错误保留 Delete、交换 Information/Identify 或错误返回 Repair Bottom 时至少一项测试会失败。

**验证命令：**

- 使用 `swiftc -parse-as-library` 编译生产策略与测试到 `/tmp/GatewayMenuPolicyTests`。
- 运行 `/tmp/GatewayMenuPolicyTests`，预期输出通过标识并以 0 退出。

### Task 2：先更新控制器 contracts 并建立 RED 基线

**文件：**

- Modify: `scripts/check_gateway_activate_header_layout.sh`
- Modify: `scripts/check_wifi_gateway_info_rows_hidden.sh`
- Modify: `scripts/check_wifi_gateway_menu_icons.sh`
- Modify: `scripts/check_wifi_gateway_child_page_modal_dismissal.sh`
- Modify: `scripts/check_device_menu_icons.sh`
- Modify: `scripts/check_device_information_menu_transition.sh`
- Modify: `scripts/check_wifi_gateway_firmware_update.sh`
- Modify: `scripts/check_wifi_gateway_repair_recovery.sh`

**接口：**

- Contracts 消费 `GatewayViewController.swift`、`WiFiGatewayViewController.swift`、本地化文件和菜单策略。
- Contracts 验证共同逻辑位于基类、WiFi 仅保留 DFU 差异。

**步骤：**

1. 调整 Info/Activate contract，要求 Gateway 基类不渲染两个 Section，WiFi 只插入 Network Connectivity。
2. 调整 Menu/Icon contract，要求共同 Delete/Information/Identify 和菜单定位由基类提供，WiFi 只提供真实 WiFi DFU。
3. 调整 Information transition 与模态保护 contract，要求共同 Information 在基类受保护、WiFi DFU 复用同一保护、恢复逻辑位于基类。
4. 增加 4G DFU、本地化 Identify、Save Only/Hidden 的检查。
5. 运行全部受影响 contracts，确认它们因当前 4G 页面仍为 Close、Info、DELETE+SAVE 且没有菜单而失败。

### Task 3：实现 Gateway 共同导航、菜单和子页面保护

**文件：**

- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`

**接口：**

- `GatewayViewController` 消费 `GatewayMenuPolicy`。
- 基类提供可覆盖的 DFU 类型与 DFU Action。
- WiFi 子类覆盖为 WiFi DFU，并继续打开现有 `WiFiFirmwareUpdateViewController`。

**步骤：**

1. 基类导航改为左 Back、右 More，Back 继续调用原 `closeAction()`。
2. 基类按策略构建菜单并映射四类 Action。
3. 4G DFU 复用现有 Under Development HUD；不 push、不发送命令。
4. Delete 继续调用现有 `deleteBtnAction()`，并由策略按当前权限决定是否出现。
5. Information 创建与 WiFi 当前完全相同的共享页面配置。
6. Identify 使用现有本地化 Key，并向当前 Primary Unicast Address 发送一次现有命令。
7. 把保存、启用与恢复 `isModalInPresentation` 的状态迁入基类；基类 `viewDidAppear` 恢复。
8. WiFi 子类移除共同菜单、导航和模态保护重复逻辑，仅保留 WiFi DFU 差异。
9. 运行 Task 1 测试和 Task 2 contracts；若失败，只修复本任务范围内的共同菜单行为。

### Task 4：调整 4G Section、Bottom 与本地化

**文件：**

- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

**步骤：**

1. 从 Gateway 基础 Section 移除 Info；Activate 继续不加入基础 Section。
2. 移除 WiFi 子类不再需要的 Info 过滤和空 Info Types override。
3. 配置正常时基类显示 Save Only；修复状态隐藏 Bottom View。
4. 保留 Copy Gateway Information、Repair 操作、SAVE Action 和 Delete Action 的现有 wiring。
5. 新增双语 `4g_dfu`，值均为 `4G DFU`。
6. Gateway Identify 菜单使用现有 `identify` Key。
7. 运行纯策略测试与全部受影响 contracts，确认 GREEN。

### Task 5：完整静态验证与四品牌构建

**验证：**

1. 重新运行 `GatewayMenuPolicyTests`。
2. 运行所有本次修改及直接关联的 Gateway contracts。
3. 运行 `git diff --check`。
4. 审查 `git diff`，确认没有 PID、SDK、Auth、删除协议、Associated Spaces、APN、Server Information 或无关格式化变化。
5. 直接构建 SunSmart generic iPhoneOS Debug，关闭签名。
6. 直接构建 Archipelago generic iPhoneOS Debug，关闭签名。
7. 直接构建 SLG Sync Plus generic iPhoneOS Debug，关闭签名。
8. 直接构建 SylSmart generic iPhoneOS Debug，关闭签名。

### Task 6：需求复核与实施总结

**文件：**

- Create: `docs/260814_1145_4g_gateway_page_implementation_summary.md`

**步骤：**

1. 逐项对照已批准设计，记录每项对应实现和验证证据。
2. 明确自动化未覆盖的真实 Mesh Identify、服务端 Delete、force-delete、真机手势和 `/devicesConfig` 的 `0x2703` 分类边界。
3. 记录四品牌构建结果和任何 warning，不把编译通过表述为真机或服务器验收。
4. 保持所有改动未提交，交由用户检查。
