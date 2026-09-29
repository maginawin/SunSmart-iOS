# Space Lights All 防连续点击：需求分析与开发方案

- 日期：2026-09-29
- 状态：待用户确认；本轮仅分析与规划，未修改业务代码，未运行构建或真机验证。
- 工作树：`fix-delete-devices-260928`
- 分支 / HEAD：`fix/delete-devices-260928` / `ee3b1c0a`。开始分析时工作树干净。
- 本地入口：存在 `SunSmartLocal.xcworkspace`；`.local-sdk/nordic-sig-mesh-sdk` 指向 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`。本方案不需要 SDK 修改或新 API。

## 结论

需求合理，适合实现为 All 按钮的固定操作冷却：立即发起一次控制，同时转圈并暂时忽略再次操作。用户给出的 1 / 2 / 3 秒分档可以采用，逻辑冷却期限最多 3 秒。

需要明确：转圈表达短暂操作等待，到期表示允许再次点击；不能据此判断所有设备已执行成功。当前控制链没有聚合完成回执，现场响应时间是否完全落在这些分档内尚无运行证据。本次改善快速反复切换，不承诺解决设备离线、命令丢失或网络拥塞。

建议同时确认计数口径、长按行为和页面生命周期边界，详见下文。

## 已核对的实际行为

| 环节 | 当前事实 | 对方案的约束 |
| --- | --- | --- |
| 页面入口 | `SpaceViewController` 的 Main 创建 `DevicesViewController`，后者的 Lights 创建 `DeviceLightsViewController` | 修改实际 Space Lights 页面 |
| 灯数量 | `loadDevices()` 从当前 Mesh 的 `realNodes` 取 `deviceType == .light`，保存为 `devices`；筛选结果另存 `visibleDevices` | 使用完整 `devices.count`，不使用搜索结果或总节点数 |
| All 可见性 | 灯列表非空且名称筛选匹配 All 才显示该入口 | 0 盏灯继续不显示 All；筛选隐藏后重现不能重置冷却 |
| 点击 All | `didSelectItemAt` 检查应急手动控制限制，然后翻转 `controlAllOn` 并调用全开或全关；当前没有重复点击保护 | 冷却检查必须在翻转状态和发命令之前 |
| 本地展示 | 普通模式下全开/全关先更新本地节点的 `isOn` 并刷新列表；全关保留原亮度。`routeTest` 有既有分支 | 保留原状态更新与诊断分支；冷却期间不能因刷新丢失转圈 |
| 命令链 | `LightGroupControlCommandSender.setAllOnOff` 默认向 `.allNodes` 发送 `GenericOnOffSetUnacknowledged`；本地 SDK `MeshAPI.sendMessage(message:address:)` 将其加入发送队列 | 点击计时，不以排队结束或设备执行完成计时；不改广播范围或 ACK 策略 |
| 状态展示 | `allOnOffState` 表示设备汇总状态，`controlAllOn` 表示手动控制目标，Cell 当前只有 on / off / disable | 冷却作为独立 UI 状态，不能混入设备真实状态枚举 |
| 参考交互 | Group `autoBtnAction` 进入 progress，忽略再次点击，1 秒后恢复；使用 `group_auto_progress` 和旋转动画 | 复用视觉资源及动画方法；Group Auto 保持原行为 |
| 其他入口 | All 长按打开 Space 调光面板；该面板调光与 Auto、单灯点击、Group 控制有各自路径 | 明确本次只限制 All 入口，不升级为全 Space 控制互斥 |

源码证据：

- [SpaceViewController.swift](../SunSmart/Main/Space/Controller/SpaceViewController.swift)
- [DevicesViewController.swift](../SunSmart/Main/Device/Controller/DevicesViewController.swift)
- [DeviceLightsViewController.swift](../SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift)
- [DeviceAllOnOffViewCell.swift](../SunSmart/Main/Device/View/DeviceAllOnOffViewCell.swift)
- [LightGroupControlCommandSender.swift](../SunSmart/Common/Data/LightGroupControlCommandSender.swift)
- [GroupViewController.swift](../SunSmart/Main/Group/Controller/GroupViewController.swift)

## 建议确认的交互规则

### 1. 数量与时间

| 点击当时 Space 完整 Lights 数量 N | 冷却时间 |
| --- | --- |
| N = 0 | 不显示 All；防御性忽略调用 |
| 1 ≤ N ≤ 100 | 1 秒 |
| 101 ≤ N ≤ 200 | 2 秒 |
| N > 200 | 3 秒 |

- 按当前 Lights 列表既有分类计数，包括离线灯和需要修复的灯；不新增设备能力过滤。
- 排除 Switches、Sensors、Others 等非 Lights 节点；不按元素、通道、Group 数量或在线数量计数。
- 使用点击时的数量快照。等待期间增加、删除、排序或筛选设备不改变本轮时长；下一次有效点击重新计算。

### 2. 点击与展示

1. 检查当前是否仍在冷却；若是，直接忽略，既不翻转目标状态，也不发送、排队或延长冷却。
2. 保留现有应急控制拦截；空灯列表或被应急规则拒绝时不开始冷却。
3. 对进入控制分支的有效点击，先登记截止时间，立即更新 All 的目标状态、展示转圈，再沿原链路发起一次控制。
4. 保留 All 名称及原有卡片布局，在图标位置显示 Group Auto 同风格转圈，使用品牌色；只旋转图标。
5. 到期移除转圈，按当时的现有状态逻辑重绘 All，恢复点击。不在完成回调中写入旧开关状态，不添加成功提示。

建议冷却期间同时屏蔽 All 长按进入调光面板，使 All 入口的等待交互一致。单灯控制、滚动、返回及其他页面维持现有行为。本次不限制其他控制入口、其他手机或物理开关。

### 3. 异常与生命周期

- 当前发送接口没有向本页面返回广播执行成功/失败，本次按控制尝试计时。断连或发送失败也不无限等待，不自动重发、不额外翻转目标；最多等待本轮时长后可重试。
- `.disable` 当前是汇总展示状态，并非点击入口现有的在线拦截。本次不额外用该状态增加新的连接/权限条件；沿用现有发送与应急处理。
- 状态回报、权限刷新、`reloadData`、筛选、Cell 滚出再滚入，均从页面保存的截止时间恢复显示，不重启计时。
- Lights 页面临时隐藏、切换页签后回到同一页面实例，以及前后台切换，按剩余时间恢复；期限已过立即恢复正常图标。
- **建议生命周期边界：冷却归属于当前 Lights 页面实例；完整退出 Space、或分页实际销毁重建后结束本次页面冷却。** 不跨页面重建、App 重启或不同 Space 保存；不建立全局按 Space 索引的冷却缓存。
- 如产品要求“退出重进同一 Space 也必须承接剩余时间”，需将状态放到 Space 会话层；这会扩大本次状态管理范围，应在实施前明确。默认采用上面的页面级边界。
- 离开页面清理显示层动画及定时唤醒；同一实例的截止时间保留。销毁时取消待执行任务，回调弱引用控制器；旧回调不能解除下一轮冷却。

## 开发方案与影响范围

### 必要修改

1. **`DeviceLightsViewController.swift`**
   - 增加局部冷却截止时间与可取消的到期刷新任务，以单调时间判断是否到期。
   - 统一 All 的点击准入、时长计算和显示配置；保持现有全开/全关的命令、`controlAllOn` 和亮度记录逻辑。
   - 在 Cell 创建与现有 All 状态更新入口同时配置冷却展示；补齐重新显示、前台恢复及长按入口的处理。
   - 定时任务仅负责唤醒 UI；点击是否允许以截止时间为准，避免主线程晚调度或旧回调造成状态错误。
2. **`DeviceAllOnOffViewCell.swift`**
   - 增加默认关闭的独立 loading 展示状态，复用 `group_auto_progress` / `group_auto_progress_big` 与现有旋转方法。
   - 统一图标渲染优先级，loading 期间不被 on / off / disable 的重绘覆盖。
   - 配置恢复和复用时移除自身旋转动画，确保结束后恢复静态图标，不影响其他 Cell 内容。
3. **针对性行为回归**
   - 复用现有 Swift 隔离测试脚本方式，执行实际冷却/准入方法并替换时钟和发送依赖，验证重复点击是否真正没有再次发送或翻转状态。
   - 不为本次另建 Xcode 测试工程，也不以源码字符串匹配代替行为测试。

### 复用和关联影响

- `DeviceAllOnOffViewCell` 在 Gateways / Sensors 控制器中也有注册，当前实际 All 配置与消费位于 Lights。新增 loading 默认关闭，由 Lights 显式设置，不扩大到基类 `DevicesViewCell`。
- 全开/全关发送帮助类目前仅由本页这两个动作调用，但其中还包含其他灯与 Group 能力。冷却属于页面交互，不放到 SDK 或共享发送函数中。
- Group Auto 和 Space 调光面板 Auto 各自保留当前 1 秒交互；复用视觉资源不改变它们的状态管理。
- 两个生产文件由五个品牌共享。普通品牌使用共享资源目录，Lumineux 通过已有合并资源脚本输入该目录；不新增资源或修改 target 归属。
- 预计不需要 SDK、协议、云端、数据库、导入导出或历史数据迁移；不新增可见文案。实施中若需要新增文案，补齐英文与简体中文。

## 验证与验收

### 自动验证（确认并实施后执行）

- 边界值：0、1、100、101、200、201 以及大规模数量。
- 重复点击：一次有效点击只触发一次发送与一次目标切换；期限内多次点击被忽略；到期再次点击正常反向切换；被忽略点击不延长截止时间。
- 前置拒绝：应急拦截和空列表不发送、不切换、不进入冷却。
- 状态连续性：刷新/隐藏/恢复后剩余时间正确；时间已过恢复；旧任务不能提前结束下一轮；销毁取消任务。
- 复用 `scripts/check_device_lights_state_refresh.sh` 检查既有页面可见性与节点刷新行为，按实际方法变化补齐测试替身。
- 检查 Cell 配置与复用路径；真实图标旋转效果列入人工验收，不由隔离逻辑测试推定。
- 一轮完成后运行 `git diff --check`，使用映射核实后的 `SunSmartLocal.xcworkspace` 构建一次 SunSmart Debug generic iOS、关闭签名。若实施不改变资源、公共 API 或品牌编译路径，不机械重复五品牌构建。

### 最短人工验收

1. 依次用 100 / 101 / 200 / 201 盏灯的 Space 点击 All 并连续点击：观察分别等待 1 / 2 / 2 / 3 秒，期间目标状态不反复跳变；到期后下一次点击正常。
2. 冷却期间滚动列表、刷新、筛选隐藏再显示 All、切换页签与前后台，确认剩余时间和图标恢复正确；同时验证长按被暂时忽略。
3. 验证应急控制拦截、断连后到期可重试、空 Space 不显示 All，以及 iPhone / iPad 的图标尺寸与品牌色。
4. 完整退出 Space 后重新进入，确认符合已选定的页面生命周期边界；Group Auto 和单灯操作维持原行为。

自动行为测试与编译不替代真实设备响应和 UI 体验验收。本轮没有实际执行上述验证。

## 待确认

建议按以下组合实施：**完整 Lights 数量的 1 / 2 / 3 秒分档；点击立即执行；等待期间忽略 All 点击与长按；同一页面实例保留剩余时间；完整退出或页面销毁后不跨实例保存。**
