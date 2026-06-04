# Battery Power Switch Unlinked Virtual Device Design

## 背景

真实 battery power switch 添加到 App 后，如果用户手动重置同一个物理设备，再重新添加到 site - space 中，当前流程会创建一个新的 battery power switch。旧 switch 数据仍可能保留原来的 `proxyNodeAddress`，但该地址对应的 node 已经失效，或不再是 battery power switch。

预期行为是：只要旧 BPS 的 `proxyNodeAddress` 指向的 node 不再有效，或该 node 不再是 battery power switch，旧 BPS 就应自动变更为虚拟 battery power switch。它仍保留原来的名称、link group、按键配置、scene/group 配置和 BPS metadata，并在 switches 列表中以虚线外框的 battery power switch 控件展示。

## 当前代码依据

- `DeviceSwitchesViewController` 已经优先把可识别为 `PJEightKeySwitchData` 的 switch 使用 `PJEightKeySwitchesViewCell` 展示。
- `PJEightKeySwitchesViewCell` 已根据 `PJEightKeySwitchStatus.needsDashedBorder` 支持虚线外框。
- `PJEightKeySwitchData.displayStatus` 在未绑定真实设备时返回 unbound 状态，现有状态会触发虚线外框。
- `PJEightKeySwitchRepository` 通过独立 metadata 表识别 BPS/AC power switch，旧 BPS 转虚拟时不能删除 metadata。
- `MeshNetworkManager.createDefaultSwitch(forBatteryPowerSwitch:)` 在普通添加真实 BPS 时会创建新的 switch，已有相同物理地址时才复用；手动 reset 后重新入网通常会得到新的 node 地址，因此新旧 switch 可以同时存在。

## 确认规则

旧 BPS 自动转虚拟的条件是：

- switch 有 BPS metadata，且 `powerSwitchKind == .battery`。
- switch 当前存在 `proxyNodeAddress`。
- 该地址在当前 mesh network 中找不到 node；或找到的 node 不满足 `node.isBatteryPowerSwitch == true`。

满足条件时，只清空旧 switch 的 `proxyNodeAddress`。不删除 switch，不删除 `PJEightKeySwitchRepository` metadata，不删除 link group，不清空按键、scene、bind group、battery、sync 或 more settings 信息。

## 备选方案

### 方案 A：数据归一化层处理

在 `MeshNetworkManager` 附近新增 BPS switch 归一化方法，集中修正失效的 battery power switch proxy 关系。该方法遍历 `MeshNetworkManager.instance.switchs`，识别 BPS metadata，并在 proxy node 无效或类型不匹配时清空 `proxyNodeAddress` 并持久化。

优点：
- 覆盖冷启动、切换 site/space、导入后、运行期 node 变化后的通用一致性问题。
- switches 列表、group、restore、sync 等入口都能看到一致数据。
- 复用现有 BPS metadata 和虚线外框 UI，不新增设备类型。

缺点：
- 需要谨慎控制通知发送，避免刷新循环。

### 方案 B：只在 switches 列表页面处理

在 `DeviceSwitchesViewController.updateUI()` 前修正数据。

优点：
- 改动面最小。
- 能直接解决列表展示。

缺点：
- 其他业务入口仍可能看到旧 proxy 关系，数据状态不一致。
- 导出、恢复、同步流程可能继续按真实设备处理旧 BPS。

### 方案 C：只在重新添加成功时反查旧 BPS

在添加真实 BPS 成功后扫描旧 switch 并清空失效 proxy。

优点：
- 对最初的重置后重新添加场景命中直接。

缺点：
- 无法覆盖“只要旧 proxy 失效或类型不对就转虚拟”的通用规则。
- 依赖添加流程，无法处理导入、删除、恢复、数据迁移后的失效 proxy。

推荐采用方案 A。

## 设计

### 架构

新增一个小范围的数据归一化能力，放在 `MeshNetworkManager` 或 `MeshNetwork+SunSmart.swift` 的 switch 数据维护区域。方法职责只做一件事：把失效的 battery power switch proxy 关系降级为虚拟 BPS。

建议方法语义：

- 输入：当前 `MeshNetworkManager.instance.switchs` 和当前 `meshNetwork`。
- 输出：是否发生数据变更。
- 副作用：对发生变更的 switch 保存基础 switch 表；保留并保存 BPS metadata；必要时更新内存数组中的对象类型为 `PJEightKeySwitchData`。

### 组件边界

- `MeshNetworkManager`：提供归一化入口，负责遍历、判断、保存、内存更新。
- `PJEightKeySwitchRepository`：继续作为 metadata 来源，不新增表字段。
- `DeviceSwitchesViewController`：只作为兜底触发点，不承担判断规则。
- `PJEightKeySwitchesViewCell`：不改 UI 结构，继续用现有 dashed border 逻辑。

### 数据流

1. switch 数据从数据库加载到 `MeshNetworkManager.instance.switchs`。
2. 归一化方法遍历 switch 列表。
3. 对每个 switch，尝试取得 `PJEightKeySwitchData`：
   - 如果本身是 `PJEightKeySwitchData`，直接使用。
   - 如果是基础 `DeviceSwitchData`，通过 `PJEightKeySwitchRepository.makeEightKeySwitch(from:)` 转换。
4. 只处理 `powerSwitchKind == .battery` 且 `proxyNodeAddress != nil` 的数据。
5. 检查 `proxyNodeAddress` 对应 node：
   - node 不存在：清空 `proxyNodeAddress`。
   - node 存在但 `isBatteryPowerSwitch != true`：清空 `proxyNodeAddress`。
   - node 是 battery power switch：保持不变。
6. 清空后保存 switch 基础数据和 BPS metadata，并更新内存数组。
7. 如果发生变更，触发 switches/space 刷新；如果没有变更，不发通知。

### 触发点

需要两个触发点：

- `MeshNetworkManager` 加载当前子网 switch 数据后执行一次，保证冷启动和切换网络后的数据一致。
- `DeviceSwitchesViewController.updateUI()` 前执行一次轻量兜底，处理运行期间 node 被删除、导入、恢复或类型变化后的状态。

归一化方法必须返回是否变更，页面兜底触发时只在发生变更后刷新 UI，避免重复 reload 或通知循环。

### UI 行为

旧 BPS 被清空 `proxyNodeAddress` 后：

- switches 列表仍使用 battery power switch icon。
- 控件展示虚线外框。
- 点击进入 BPS monitor，而不是普通 kinetic switch 页面。
- monitor 内按现有逻辑表现为 unlinked virtual BPS。
- 删除该虚拟 BPS 时走现有无真实设备删除路径，不发送真实 BPS reset。

不新增本地化文案，不新增 icon，不改变 AC power switch 和普通 kinetic switch 展示。

### 错误处理

- 如果当前没有 `meshNetwork`，归一化不做变更。
- 如果 metadata 读取失败，说明该 switch 不是可识别 BPS，不处理。
- 如果保存基础 switch 失败，不应删除 metadata 或内存数据；保留当前状态，避免造成数据丢失。
- 如果保存 metadata 失败，应避免只更新内存但未持久化的半状态。实现计划中需要明确保存顺序和失败回滚策略。

### 测试与验证

静态验证：

- 搜索确认归一化只处理 `powerSwitchKind == .battery`。
- 确认 AC power switch 不会因为 offline 或 node state false 被清空。
- 确认普通 kinetic switch 不受影响。

功能验证：

- 准备一个真实 BPS switch 数据，删除或失效其 proxy node 后进入 switches 列表，预期旧 BPS 显示虚线外框。
- 同一个物理 BPS reset 后重新添加，预期新 BPS 正常显示，旧 BPS 变为虚线虚拟 BPS。
- 旧 BPS 点击后仍进入 BPS monitor。
- 删除旧虚拟 BPS 时不发送真实 BPS reset。

构建验证：

- 运行 SunSmart Debug iPhoneOS 构建：
  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 范围外

- 不合并新旧 BPS 数据。
- 不自动把旧虚拟 BPS 绑定到新真实 BPS。
- 不改变 battery power switch 添加流程的默认新建设备行为。
- 不新增 Auth 信息。
- 不重构 switch 列表 UI。
- 不修改本地化、资源、target 配置或依赖。
