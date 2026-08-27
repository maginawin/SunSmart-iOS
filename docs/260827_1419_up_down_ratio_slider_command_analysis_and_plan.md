# Up/Down Ratio 滑条命令问题分析与开发计划

## 结论

用户描述基本正确。

- `DeviceUpDownRatioControlView` 同时包含 `Up/Down Ratio` 标题、滑条、当前比例文案和 5 个快捷按钮。
- 快捷按钮会同时触发本地值更新与最终提交回调，因此单设备页会进入 `sendUpRatioValue(_:)`，发送 `SunricherVendorSet(function: .upDownLightUpRatio(...))`。
- 滑条拖动时只触发本地值更新；手指离开时，底层滑条虽然提供了结束回调，但共享 Ratio 组件因为“值与当前值相同”提前返回，没有触发最终提交回调，所以不会发送 Up/Down Ratio Vendor SET。
- 同一 `DeviceUpDownRatioControlView` 还被 Group 页面复用，因此 Group 页滑条的最终组播 SET 也存在相同漏发问题；快捷按钮不受影响。

推荐采用方案二，并按确认结果将发送频率定义为“滑动期间每 0.3 秒最多发送一次最新变化值，松手后无条件再发送一次最终值”。这样能够获得近似连续调节效果，同时限制 Mesh 流量，并保证最终设备目标值与 App 展示值一致。

## 当前实现证据

### UI 与事件

`SunSmart/Main/Device/View/DeviceUpDownRatioControlView.swift`：

- `valueChanging` 用于实时更新页面状态。
- `valueChanged` 用于最终提交。
- 滑条普通 value callback 会先调用 `setUpValue(... notifyChanging: true ...)`。
- 滑条 throttle callback 当前只处理 `ended == true`，再调用 `setUpValue(... notifyChanged: true)`。
- 快捷按钮一次调用 `setUpValue(... notifyChanging: true, notifyChanged: true)`。
- `setUpValue` 在新值与 `currentUpValue` 相同时直接返回。

因此滑条事件顺序为：

1. 拖动事件已把 `currentUpValue` 更新成最终值。
2. 松手事件携带同一个最终值再次进入 `setUpValue`。
3. 相同值 guard 提前返回。
4. `valueChanged` 未触发，控制器没有发送命令。

快捷按钮从旧值直接切换到目标值，在同一次调用中依次触发 changing 和 changed，因此能够发送命令。

### 单设备命令链路

`SunSmart/Main/Device/Controller/DeviceLightViewController.swift`：

- `valueChanging` 只调用 `applyLocalUpRatioValue(_:)`，更新 `node.upRatio` 和页面展示。
- `valueChanged` 调用 `sendUpRatioValue(_:)`。
- `sendUpRatioValue(_:)` 使用单设备 Vendor Model 发送有 ACK 的 `upDownLightUpRatio` SET，超时为 7 秒。
- 成功后更新 `confirmedUpRatioValue` 并保存本地预配置；失败或超时会回滚 UI 与本地内存值，并显示失败提示。

### 底层滑条能力

`SunSmart/Common/View/CustomDeviceSlider.swift` 已具备：

- 可配置的 throttle interval，当前默认值为 0.3 秒。
- 滑动过程中按 interval 回调最新变化值。
- `touchesEnded` 时停止 timer，并无条件触发 ended 回调。

因此不需要另建一套页面定时器。Ratio 组件沿用统一的 0.3 秒 interval，并正确向上层区分 sampling 与 final 两种事件。

## 方案对比

### 方案一：只在松手时发送

优点：

- 改动最小。
- Mesh 流量最低。
- 保持原设计文档中“拖动只更新 UI，结束才发送”的语义。

缺点：

- 拖动过程中设备无实时反馈，用户不能边拖边观察上下灯比例效果。

### 方案二：0.3 秒采样 + 松手最终发送

优点：

- 长时间拖动时可观察设备比例逐步变化。
- 每 0.3 秒最多一条，相比每个 valueChanged 都发送仍可控制 Mesh 压力。
- 松手后再发送最终值，能够覆盖最后一次采样与页面最终值之间的差异。

风险：

- Vendor SET 是有 ACK 的消息，连续发送时不能让多个同源、同 response opcode、同 function code 的请求并发等待回包，否则旧响应可能干扰新请求的结果处理。
- 中间样本失败不应频繁回滚 UI 或连续弹失败 Toast，否则会破坏拖动体验。
- 最终提交必须独立于“值是否变化”的 UI 去重判断；即使最终值与最后一个样本完全相同，也必须再次发送。

综合体验与流量，推荐方案二。

## 推荐开发设计

### 1. 明确 Ratio 组件的三类事件

在 `DeviceUpDownRatioControlView` 中明确区分：

- `changing`：UISlider 每次数值变化，用于立即刷新 Ratio 文案、快捷按钮选中态、顶部灯光示意和 `node.upRatio`，不直接作为最终持久化依据。
- `sampling`：手指仍在滑动，按 0.3 秒间隔输出当前最新值；只有采样值相对上次发送值发生变化时才需要发送，避免手指停住时重复发送同一个值。
- `final`：手指离开、取消滑动或点击快捷按钮时触发；不受内部 UI 相同值去重影响，必须无条件向控制器交付最终值。

实现时保留 UI 刷新的相同值去重优化，但把命令事件通知从该 guard 中分离，避免再次出现“UI 无需刷新，所以业务事件也被吞掉”的问题。

Ratio 组件的 slider throttle interval 使用 0.3 秒，与 `CustomDeviceSlider` 的全局默认值一致；不修改全局默认值，避免影响亮度、CCT、DALI、校准等其它滑条。

### 2. 单设备页采用分阶段发送策略

在 `DeviceLightViewController` 中：

- sampling：使用现有有 ACK 的 Vendor SET 发送当前采样值，用于设备预览；成功后只更新内存中的“设备最后已确认值”，不写数据库；单次采样失败不回滚当前拖动 UI，也不弹连续失败提示。
- final：复用现有有 ACK 的 SET 成功/失败处理；成功后更新 confirmed 值并持久化，失败或超时回滚到最后一次已确认值。
- 快捷按钮仍走 final，一次点击只提交一次，不启动采样。

为避免同一种 Vendor ACK 并发匹配，增加轻量发送协调状态：

- 同一设备同一时刻只处理一个需要结果确认的 Ratio SET。
- 每 0.3 秒采样只保留最新待发值；如果发送通道正忙，旧的未发采样值被新值覆盖。
- 松手 final 覆盖所有待发 sampling，并作为下一条必须发送的请求。
- final 即使等于最近一次 sampling，也必须再发送。
- 使用交互代次或请求序号忽略过期完成回调，避免快速连续拖动时旧请求覆盖新 UI。

sampling 与 final 都串行等待对应 ACK。正常 Mesh 环境下按 0.3 秒节奏采样；若前一条 ACK 较慢，则 timer 仍每 0.3 秒采样，但发送层只合并保留最新值，不并发创建相同 Vendor response matcher。只有 final 成功才执行正式持久化。最终失败时回滚到设备最后已确认值，而不是任意较早的初始值。

### 3. Group 页发送边界

初始确认范围是 Group 页只修复 final。真机测试通过后，产品进一步确认 Group 页也启用持续预览，最终边界调整为：

- 滑动期间消费共享 Ratio 组件的 0.3 秒 sampling，每次向组地址发送最新 Up/Down Ratio。
- sampling 只发送并更新内存展示，不保存各节点预配置。
- final 无条件再向组地址发送最终值，并保存各节点预配置。
- 快捷按钮仍只触发一次 final，不启动 sampling。
- Group 继续调用现有 fire-and-forget `MeshAPI.sendMessage(message:address:)` 重载，App 不注册 ACK waiter、不等待结果，也不进行失败提示或回滚。

需要注意：当前发送的 `SunricherVendorSet` 类型仍实现 `StaticAcknowledgedVendorMessage`，SDK 没有 Up/Down Ratio 专用 Unack 消息类型。因此“fire-and-forget”只表示 App 不等待 ACK，不代表设备协议层一定不返回 Vendor Status；真机仍需观察多节点回包与 Mesh 压力。

### 4. 生命周期与状态边界

- 页面退出、节点切换或控制器释放时停止 Ratio 交互会话，忽略迟到回调。
- 页面进入时现有 Vendor GET 仍保留；用户开始编辑后，迟到的初始 GET 不覆盖用户值。
- 采样过程只更新内存和可见 UI，不写本地数据库。
- final ACK 成功后才持久化；final 失败后 App 回滚，确保 App 最终展示不宣称一个未经设备确认的值。
- 不修改协议编码、SDK Vendor message 类型、设备能力判断、云同步和数据库结构。

## 预计修改范围

- `SunSmart/Main/Device/View/DeviceUpDownRatioControlView.swift`
  - Ratio 使用统一的 0.3 秒 throttle。
  - 将 sampling/final 事件与 UI 去重解耦。
  - 快捷按钮映射为 final。
- `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`
  - 接入 sampling 与 final。
  - 增加最新值合并、最终值优先和过期回调保护。
  - 保留现有 final ACK、成功保存、失败回滚语义。
- `SunSmart/Main/Group/Controller/GroupViewController.swift`
  - sampling 使用现有组播发送方式，但不持久化。
  - final 无条件再次组播，并沿用现有节点预配置保存行为。
- 新增聚焦测试或 contract 检查文件。
  - 覆盖相同值 final 不被吞、0.3 秒 sampling、final 优先、快速连续手势旧回调不覆盖新状态、Group sampling/final 持久化边界。

不预计修改 NordicSigMeshSDK。本工程当前使用远程 `release` 包，锁定 revision `9504e5ba7286205f8d4749d8127bf2178b19d9a2`；该版本已经包含所需 Vendor SET/GET/Status 能力。

## 验证计划

### 自动与源码契约

- 滑动不足 0.3 秒：过程中不发 sampling，松手恰好触发一条 final。
- 滑动超过 0.3 秒且值持续变化：每 0.3 秒最多一条 sampling。
- 手指停在同一位置：不重复发送相同 sampling。
- final 与最近 sampling 相同：仍额外触发一条 final。
- `touchUpInside`、`touchUpOutside`、`touchCancel` 均触发 final。
- 快捷按钮：只触发一条 final。
- 快速连续两次拖动：旧请求完成不覆盖新一轮 UI/confirmed 状态。
- Group 页：滑动过程中按 0.3 秒最多组播一次最新变化值，结束无条件再发送一条最终组播。
- 执行 `git diff --check` 和聚焦 contract tests。

### 构建

该 UI 和控制器属于共享代码，按顺序执行四个 unsigned generic iPhoneOS build：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

构建只证明共享源码和 target 集成通过，不等同于真实滑条事件、BLE Mesh 或设备比例变化验收。

### 真机与 Mesh 验收

- 在支持 Up/Down Ratio 的真实设备页抓取 App 日志或 Mesh 包。
- 短拖动后松手：确认最终 SET payload 为 `[0x53, 0x02, upRatio]`，且设备返回成功 RET。
- 长拖动：确认 sampling 间隔约 0.3 秒、数值随 UI 变化、松手后存在最后一条 final。
- 校验最后一条发送值、设备 GET 读回值、App 展示值三者一致。
- 覆盖 0/100、50/50、非快捷值（如 63/37）、快速来回拖动、触摸取消、Mesh 弱网/超时和页面立即退出。
- 单独回归快捷按钮与 Group 页最终组播行为。

## 待确认实施口径

建议按以下口径实施：

1. 选择方案二。
2. 按最终确认改为“每 0.3 秒最多发送一次最新变化值”；相同值不重复占用 Mesh。
3. 单设备页启用 sampling + final；初始范围中 Group 页只修复 final，真机测试通过后进一步确认 Group 页也启用 0.3 秒 sampling + final。
4. final 始终再发送一次，即使它与最后一个 sampling 相同。
5. sampling 失败不打断拖动、不弹 Toast；final 失败才按现有逻辑提示并回滚。

确认以上 5 点后再进入代码实现。

## 实施结果

已按确认口径完成：

- Ratio 滑条显式使用 0.3 秒 interval，没有修改 `CustomDeviceSlider` 的全局默认 interval。
- sampling 与 final 已从 UI 相同值去重中分离；滑动期间由既有 throttle 只回调最新变化值，松手 final 无条件交付，因此与最后一次 sampling 相同也会再发送。
- 单设备页通过轻量调度器串行发送有 ACK 的 Vendor SET；待发 sampling 合并为最新值，final 替换尚未发送的 sampling，并保持必须发送。
- sampling 失败不回滚、不提示、不持久化；final 沿用成功保存、失败提示与回滚语义。
- Group 页已绑定 sampling：滑动期间按 0.3 秒 fire-and-forget 组播最新变化值但不持久化；final 无条件再次组播并保存节点预配置。
- 触摸取消的 final 能力采用默认关闭、Ratio 显式开启的方式，不改变亮度、CCT、DALI、校准等其它共享滑条的取消行为。
- NordicSigMeshSDK 未修改，继续使用远程 `release@9504e5b`。

自动验证已覆盖调度器合并/排序、相同值 final、取值边界、Ratio 事件契约、Group sampling/final 持久化边界、四 target 源文件成员关系和原有 Up/Down Light 产品支持契约。四个共享 target 的 unsigned generic iPhoneOS 构建均通过：SunSmart、Archipelago、SLG Sync Plus、SylSmart。

上述结果证明源码契约与构建集成通过；真实设备的 Mesh 采样节奏、ACK/超时表现、最终值一致性和页面布局交互仍需按“真机与 Mesh 验收”章节执行。
