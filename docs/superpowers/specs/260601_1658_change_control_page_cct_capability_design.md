# Change Control Page CCT 能力语义优化设计

## 背景

当前 `Site - Space - More - Device Parameter Settings` 中的 `Change Control Page` 会影响 `Node.effectiveSupportCct`。当真实拥有 CCT Model 的设备被设置为 `Single White` 后，当前代码会把该设备当作“不支持有效 CCT”的设备处理。

这与早期设计一致，但现在业务预期已经调整：

- `Single White` 只表示单设备页面按单白光设备展示和控制。
- 真实拥有 CCT Model 的设备，在组控、批量控制、Scene、Profile 等跨设备或自动化入口仍应被视为拥有 CCT 能力。

## 当前判断

当前 SDK 中存在两层能力：

| 能力 | 当前含义 |
|---|---|
| `rawSupportCct` | 设备 Composition 中存在 CCT/CTL Temperature Model |
| `effectiveSupportCct` | `rawSupportCct && effectiveChangeControlPage != .singleWhite` |

因此，所有使用 `effectiveSupportCct` 的入口都会被 `Change Control Page = Single White` 影响。已确认受影响入口包括：

| 入口 | 当前影响 |
|---|---|
| 单设备控制页 | 隐藏 CCT 滑条和 CCT 展示 |
| 设备 Cell / Header | 只展示亮度，不展示 CCT 属性 |
| 组控制页 | 组能力合集可能没有 CCT，隐藏组 CCT 滑条 |
| 批量控制 | 多设备控制可能不显示 CCT |
| Scene 创建/设置 | 场景属性弹窗可能不显示 CCT |
| Scene 同步/执行 | Single White 设备跳过 CCT 目标和 CCT 比较 |
| Profile Power On | Custom 可能不显示或不同步 CCT |
| 设备详情/基础控制/DALI 单设备 | 按单设备展示语义隐藏 CCT |

## 已确认需求

| 场景 | 预期 |
|---|---|
| 单设备相关页面 | `Single White` 后继续隐藏 CCT |
| 设备列表 Cell | `Single White` 后继续只展示亮度百分比 |
| 组控制页 | 只要设备真实拥有 CCT Model，就参与 CCT 能力合集 |
| 批量控制 | 真实拥有 CCT Model 的设备参与 CCT 控制 |
| Scene 创建/设置/执行/同步 | 真实拥有 CCT Model 的设备需要 CCT 属性、目标和同步比较 |
| Profile Power On Custom | 真实拥有 CCT Model 的设备需要 CCT 选择、保存和同步 |
| Device Parameter Settings | 继续按 `rawSupportCct` 展示 Change Control Page 与 Absolute CCT Range |

## 推荐方案

拆分“真实控制能力”和“单设备展示能力”。

| 能力 | 语义 | 使用范围 |
|---|---|---|
| `rawSupportCct` | 设备真实 Mesh CCT 能力 | Device Parameter Settings、底层参数下发判断 |
| `effectiveSupportCct` | 跨设备/自动化入口的有效 CCT 能力，等同真实 CCT 能力 | Group、Scene、Profile、批量控制、同步状态 |
| `singleDeviceDisplaySupportCct` | 单设备 UI 展示能力，受 Change Control Page 影响 | 单设备控制页、设备 Cell、Header、设备详情、DALI 单设备 |

`singleDeviceDisplaySupportCct` 的规则为：

| 条件 | 结果 |
|---|---|
| `rawSupportCct == false` | 不显示 CCT |
| `rawSupportCct == true && effectiveChangeControlPage == .singleWhite` | 单设备页面不显示 CCT |
| `rawSupportCct == true && effectiveChangeControlPage == .tunableWhite` | 单设备页面显示 CCT |

`effectiveSupportCct` 调整为跨设备语义：

| 条件 | 结果 |
|---|---|
| `rawSupportCct == false` | 不支持 CCT |
| `rawSupportCct == true` | 支持 CCT |

## 调用点设计

### 保留单设备隐藏 CCT

以下入口应改用 `singleDeviceDisplaySupportCct`：

| 文件 | 用途 |
|---|---|
| `DeviceLightViewController.swift` | 主单灯控制页 CCT 滑条、CCT 状态、背景色 |
| `DeviceLightBasicController.swift` | 基础控制页 row count、CCT cell、单设备 Scene 信息展示 |
| `DeviceLightHeaderView.swift` | Header CCT 属性展示和背景色 |
| `DevicesViewCell.swift` | 设备 Cell CCT 颜色/属性展示 |
| `DeviceInformationViewController.swift` | 单设备详情中的 Scene CCT 展示 |
| `DaliMasterViewController.swift` | DALI 单设备 CCT 控制与展示 |

这些入口仍然体现 `Change Control Page = Single White` 的 UI 目的：用户在单设备页面只看到单白光控制。

### 开放真实 CCT 能力

以下入口应继续或改为使用跨设备能力，也就是新的 `effectiveSupportCct` 语义：

| 文件 | 用途 |
|---|---|
| `MeshNetwork+SunSmart.swift` | `Group.effectiveSupportCct`、`Group.effectiveCctRange`、`Group.cct`、`SceneExecuteData.deviceTarget` |
| `GroupViewController.swift` | 组 CCT 滑条显示、组 CCT 本地状态更新 |
| `GroupServer.swift` | 组场景同步下发 CCT |
| `DeviceLightsViewController.swift` | 多设备批量控制支持 CCT、批量 CCT 下发 |
| `SceneAddViewController.swift` | Scene 创建页 CCT 范围、属性弹窗、预览、保存 |
| `SceneSettingsViewController.swift` | Scene 设置页 Group 属性弹窗、预览 |
| `ScenesViewController.swift` | Scene 执行后的本地 CCT 状态更新 |
| `Node+MessageHandles.swift` | Scene 同步和 Profile Power On 下发 CCT |
| `Node+SyncData.swift` | Scene/Profile needSync 目标 CCT 判断 |
| `ProfileSettingsViewController.swift` | Power On Custom CCT 范围、显示、保存 |

这些入口处理的是组、场景、配置文件或批量操作，不应受单设备展示模式影响。

## 数据流

`Change Control Page` 保存逻辑不变：

1. Device Parameter Settings 写入 `node.changeControlPage`。
2. 本地保存并通过现有空间数据同步到云端。
3. `Single White` 不改变设备 Composition Data，也不改变真实 CCT Model。
4. 单设备页面读取 `singleDeviceDisplaySupportCct` 决定是否展示 CCT。
5. Group、Scene、Profile、批量控制读取 `effectiveSupportCct` 决定是否提供 CCT 能力。

`Absolute CCT Range` 逻辑不变：

- 真实 CCT 设备继续拥有 `effectiveCctRange`。
- Group/Scene/Profile 使用真实 CCT 设备的范围做并集。
- 下发前继续按设备自身范围 clamp。

## 兼容性

不做数据迁移。

已有 `changeControlPage = singleWhite` 的设备自动获得新语义：

- 单设备页面仍隐藏 CCT。
- 组控、批量、Scene、Profile 开始按真实 CCT Model 开放 CCT。

特殊默认 Single White 产品仍保留默认单设备隐藏 CCT；如果设备真实拥有 CCT Model，它也会在 Group、Scene、Profile 中被视为 CCT 设备。

## 风险与控制

| 风险 | 控制方式 |
|---|---|
| 单设备页面误显示 CCT | 单设备相关入口全部显式使用 `singleDeviceDisplaySupportCct` |
| Scene/Profile 同步状态与下发目标不一致 | `SceneExecuteData.deviceTarget`、`isSynced`、`ProfileType.targetPowerUpCct` 使用同一跨设备能力语义 |
| 纯 Dim 设备收到 CCT | 跨设备能力仍基于真实 `rawSupportCct`，纯 Dim 设备不会参与 CCT |
| 旧文档与新语义冲突 | 本设计明确覆盖早期“Single White 等于有效无 CCT”的设计 |

## 验证计划

### 静态检查

- 单设备相关页面使用 `singleDeviceDisplaySupportCct`。
- Group、Scene、Profile、批量控制使用 `effectiveSupportCct`。
- Device Parameter Settings 继续使用 `rawSupportCct`。

### 构建验证

运行：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

### 行为验证

| 场景 | 预期 |
|---|---|
| CCT 设备设置为 Single White 后进入单设备控制页 | 不显示 CCT 滑条 |
| CCT 设备设置为 Single White 后查看设备 Cell | 只展示亮度，不展示 CCT 属性 |
| Single White CCT 设备加入 Group | Group 页面显示 CCT 滑条 |
| Group 中混合 Single White CCT、Tunable White CCT、纯 Dim 设备 | CCT 只下发给真实 CCT 设备，纯 Dim 只走亮度 |
| Scene 设置页长按 Group | 弹窗显示 CCT，保存时记录 CCT |
| Scene 同步 Single White CCT 设备 | 设备参与 CCT 目标与同步比较，不因 CCT 缺失反复 needSync |
| Profile Power On 选择 Custom | 显示 CCT，保存后同步给真实 CCT 设备 |

## 非目标

- 不改 Device Parameter Settings 的 UI 和保存语义。
- 不迁移历史数据。
- 不修改设备 Composition Data 或底层 Model 解析。
- 不改变 Absolute CCT Range 的输入范围、下发方式和云同步字段。
- 不新增 Auth 或权限逻辑。
