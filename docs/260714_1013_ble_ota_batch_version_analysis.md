# BLE OTA Batch 固件版本规则设计规范

## 1. 结论

需求方向合理，但不能继续依赖 `String.compare(_:options: .numeric)`，也不能抽象成普通的升序版本比较器。

原因是：当基础版本 `x.y.z` 相同、设备与所选固件都有 `batch` 且 `batch` 不同时，规则允许双向更新。例如 `1.2.3.10` 可以更新到 `1.2.3.9`，`1.2.3.9` 也可以更新到 `1.2.3.10`。这不满足普通大小关系的反对称性，必须建模为有方向的“设备版本能否更新到所选固件版本”策略。

本次范围只影响 BLE OTA：

- `Site > Space > More > Firmware update via BLE`
- `Site > 右上角菜单 > Firmware update > Firmware update via BLE`
- 从上述 BLE OTA 页面进入的目标固件查看、服务器固件提示和下载流程

Mesh OTA 继续使用当前数字大小比较规则。

## 2. 当前代码事实

两个入口最终都创建 `BleFirmwareUpdateViewController`，所以不需要分别修改入口：

- Space 入口：`SunSmart/Main/Space/Controller/SpaceMoreViewController.swift`
- Site 入口：`SunSmart/Main/Site/Controller/SiteViewController.swift`
- 共享页面：`SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift`

BLE OTA 当前存在以下独立版本判断点：

1. 页面初始化时比较本地所选固件与设备固件，设置 `node.enableUpgrade`。
2. BLE 扫描发现设备后再次比较版本，并结合 RSSI `>= -80 dBm` 设置 `node.enableUpgrade`。
3. `FirmwareUpdateTypeData.upgradedNodes` 计算“已升级”数量。
4. `BleFirmwareTypeUpdateViewCell` 比较服务器版本与本地所选版本，显示服务器存在新版本的标志。
5. `FirmwareVersionViewController` 比较服务器版本与本地所选版本，决定是否显示并允许下载。

其中 `FirmwareVersionViewController` 同时被 BLE OTA 和 Mesh OTA 使用。若直接替换其比较规则，会越过本次“只影响 BLE OTA”的范围，因此需要由 BLE 流程显式传入新策略，Mesh 流程保留默认旧策略。

## 3. 完整规则矩阵

以下 `D` 表示设备版本，`T` 表示所选目标固件版本；先按数字依次比较前三段 `x.y.z`。

| D 与 T 的基础版本关系 | D 的 batch | T 的 batch | 是否允许更新 |
| --- | --- | --- | --- |
| `T.x.y.z > D.x.y.z` | 任意 | 任意 | 是 |
| `T.x.y.z < D.x.y.z` | 任意 | 任意 | 否 |
| 相同 | 无 | 无 | 否 |
| 相同 | 无 | 有 | 否 |
| 相同 | 有 | 无 | 是，目标为正式固件 |
| 相同 | 有 | 有且相同 | 否 |
| 相同 | 有 | 有且不同 | 是，不比较 batch 大小 |

这张矩阵补全了需求中隐含但需要明确的两点：

- 基础版本不同时，是否存在 `batch` 完全不影响结果。
- 同基础版本、设备正式版、目标 batch 版时，正式版不会回到 batch 版。

## 4. 解析与异常规则

建议只接受两种格式：三个数字段 `x.y.z`，或三个数字段加一个非空 batch 标识 `x.y.z.b`。

- `x`、`y`、`z` 按无符号整数解析和比较。
- `batch` 只判断是否存在以及是否相同，不参与大小比较。
- 服务端现有入口已经移除版本前缀 `v`，保持该边界行为，不在核心策略中做宽松字符串替换。
- 缺失版本或格式非法时采用 fail-closed：不允许更新，也不计入“已升级”数量，避免错误放行 OTA。
- RSSI、扫描发现状态、升级状态、权限和 composition hash 提示仍是独立条件，不并入版本策略。

## 5. 方案决策记录

### 方案 A：BLE 专用的方向性版本策略（已确认采用）

新增纯 Swift、无 UIKit 依赖的 BLE 版本解析与判定单元，公开方向性接口，例如“从设备版本更新到目标版本是否允许”。BLE controller、BLE cell 和 BLE 固件下载页统一调用；共享下载页通过注入策略区分 BLE 与 Mesh。

优点：规则只有一个真值源，能覆盖所有 BLE 消费点；Mesh 行为不变；可用表驱动方式独立测试。缺点：需要新增一个源文件，并将它加入四个 App target，因为相关 BLE 页面本身属于四个共享 target。

### 方案 B：在现有调用点分别增加条件分支

直接在 controller、model、cell 和下载页各自识别第四段。

优点：表面改动直接。缺点：至少五个判断点容易漂移；下载可用性、设备可选状态和“已升级”数量可能出现不一致；后续难以证明规则完整，不推荐。

### 方案 C：全局替换固件版本比较规则

让 BLE OTA 和 Mesh OTA 共用 batch 规则。

优点：统一所有 OTA 表现。缺点：违反已确认的范围，且 Mesh 分发流程有多处自己的顺序比较语义；风险明显高于本次需求，不采用。

## 6. 推荐设计

### 6.1 版本策略

建立 BLE 专用策略，输出至少三种结果：允许更新、不允许更新、版本无效。不要只返回普通 `ComparisonResult`。

方向性输入固定为：

- 当前版本：设备固件版本，或下载页当前缓存版本
- 目标版本：所选固件版本，或下载页服务器版本

先解析并比较基础版本，再按规则矩阵处理 batch。

### 6.2 BLE 页面状态

`BleFirmwareUpdateViewController` 的初始化和扫描回调都调用同一个版本策略。只有“版本允许更新”且设备已被 BLE 扫描发现、RSSI 不低于 `-80 dBm` 时，才设置 `node.enableUpgrade = true`。

“已升级”数量也使用同一规则解释：有效版本且当前设备不需要更新到所选目标固件时计入；非法或缺失版本不计入，避免把无法解析误报为已升级。

### 6.3 固件提示与下载

BLE cell 中服务器“有新版本”标志使用同一方向性策略，将本地缓存版本视为当前版本、服务器版本视为目标版本。

`FirmwareVersionViewController` 增加可注入的版本判定策略：

- BLE OTA 创建页面时传入 batch-aware 策略。
- Mesh OTA 不传，继续使用现有数字大小规则。

这样同基础版本的两个不同 batch 能在 BLE 流程中提示并下载，而 Mesh 页面行为不变。

### 6.4 不变范围

- 不修改两个入口的导航和权限判断。
- 不修改 Mesh OTA controller、分发者选择、设备选择及 Mesh cell 的比较。
- 不修改数据库结构、服务端接口和固件包内容。
- 不新增用户可见文案，因此不涉及本地化资源变更。
- 不修改 SDK；版本规则属于 App 的 BLE OTA 产品策略。

## 7. 验证设计

由于工程当前没有 XCTest target，建议为纯 Swift 策略增加可由 `swiftc` 编译运行的表驱动测试文件，覆盖：

- 上述七类规则矩阵。
- `x`、`y`、`z` 分别增大或减小。
- 两个 batch 的数值大小方向相反但仍允许更新。
- 相同 batch、不带 batch 的相同正式版本。
- 缺段、多段、空段、非数字基础段、缺失版本。

随后执行：

1. 运行纯 Swift 表驱动测试。
2. 检查 `git diff --check`。
3. 按项目规则使用 iPhoneOS `xcodebuild` 验证 `SunSmart`。
4. 因新增源文件属于共享页面，继续构建 `Archipelago`、`SLG Sync Plus`、`SylSmart`，确认四个 target 的 source membership 完整。
5. 手工核对两个 BLE 入口最终表现一致，并确认 Mesh OTA 未切换到新策略。

## 8. 实施任务草案

1. 先建立 BLE 版本策略及完整失败测试，再实现最小解析和方向性判定。
2. 将 BLE controller 的初始化与扫描回调迁移到统一策略。
3. 将 BLE 页面“已升级数量”和服务器新版本标志迁移到统一策略。
4. 为共享固件下载页加入可注入策略，BLE 使用新规则，Mesh 使用默认旧规则。
5. 完成表驱动测试、静态检查、四 target iPhoneOS 构建及入口回归检查。

## 9. 验收标准

- 两个 BLE OTA 入口对相同设备和所选固件给出一致的可更新结果。
- 表中七类有效版本组合全部符合规则矩阵。
- 当基础版本不同时，batch 的存在与内容不改变前三段数字比较结果。
- 当基础版本相同且两个 batch 不同时，不论 batch 数值谁大都允许更新。
- 设备为同基础版本正式版、目标为 batch 版时禁止更新。
- 设备为同基础版本 batch 版、目标为正式版时允许更新。
- 无效或缺失版本不会开放 BLE OTA，也不会被计为已升级。
- 服务器版本与本地缓存版本的 BLE 提示、下载状态采用同一规则。
- Mesh OTA 的版本比较行为与改动前一致。
- `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target 均通过 iPhoneOS Debug 无签名构建。

本规范已于 2026-07-14 确认采用方案 A。后续实施计划必须保持 BLE-only 范围，不得将 batch 规则扩展到 Mesh OTA。
