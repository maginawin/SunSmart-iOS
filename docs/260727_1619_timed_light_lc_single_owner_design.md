# Timed 双 Scheduler 按动作单 Owner 设计

## 1. 决策

对每个 `node + schedule index` 保持一个有效物理 Owner，但 Owner 由逻辑 Action 决定：

| Action | 双 Scheduler 设备 Owner | 单 Scheduler 设备 Owner |
|---|---|---|
| Auto/On（`turnOn`） | Light LC Scheduler Setup | 唯一 Scheduler Setup |
| Off（`turnOff`） | 普通 Scheduler Setup | 唯一 Scheduler Setup |
| Scene Recall（`sceneRecall`） | 普通 Scheduler Setup | 唯一 Scheduler Setup |

Target 是 Devices、Groups 或 Scenes 不参与 Model 选择；设备当前是否加入 Group 也不参与 Model 选择。

## 2. 目标

1. Auto/On 稳定由 Light LC Scheduler 执行，使双模型灯具进入 AUTO。
2. Off 与 Scene Recall 延续普通 Scheduler 的模型语义。
3. 同一个 index 在设备上最终只保留一个有效 entry。
4. 删除时不依赖当前 Action 或历史 Owner，清理全部 Scheduler Setup Models。
5. 单 Scheduler 设备保持兼容。

## 3. 写入规则

### 3.1 Set / Edit / Enable / Disable

对每个节点：

1. 根据逻辑 Action 选择 Owner；
2. 向全部非 Owner Scheduler 写入同 index 的无效 entry；
3. 向 Owner 写入目标 entry。

清理必须先于 Owner 写入，即使本地缓存认为非 Owner 没有该 index，也仍发送清理消息。这样可迁移旧版本或异常写入留下的跨 Model 残留。

编辑 Action 时同样适用：

- Auto/On 改为 Off 或 Scene Recall：先清 Light LC，再写普通 Scheduler；
- Off 或 Scene Recall 改为 Auto/On：先清普通 Scheduler，再写 Light LC。

禁用 entry 仍保留逻辑 Action，因此禁用状态也能选择正确 Owner。

### 3.2 Delete

删除直接向节点全部 Scheduler Setup Models 的同 index 写入无效 entry，不根据当前 Action 推断历史位置。

只有全部 Model 的该 index 状态均已知且均无效时，才完成本地待删除目标清理。任一 Model 清理失败或状态未知都保留重试条件。

### 3.3 历史入口

Timed 新增、编辑、启用、禁用、Group/Space 同步与设备恢复统一复用同一个 Schedule 消息生成入口，避免局部代码绕过 Action Owner 规则。

## 4. 缓存与同步判定

### 4.1 Model-aware 缓存

每个 Scheduler 响应按来源 Model 写入：

- `allSchedulerModelEntrys[model][index]`：每个 Model 的真实数据；
- `schedulerActions[index]`：按 Action Owner 规则生成的兼容投影。

App 投影优先使用本地 Schedule 的目标 Action；删除态 `noAction` 回退到设备 entry 自带的 Action，避免在物理清理完成前过早隐藏残留。

### 4.2 `needsSync`

已同步必须同时满足：

1. Action 对应 Owner 的 entry 等于 App 目标 entry；
2. 所有非 Owner Model 的状态已知；
3. 所有非 Owner 的同 index 均无有效 entry。

### 4.3 `needsDelete`

节点不再属于 Target 时，只要任一 Scheduler Model 的同 index 有效，或任一 Model 状态未知，就继续执行删除。

## 5. 读取规则

1. 遍历节点全部 Scheduler Setup Models；
2. 每个 Scheduler Status 只驱动来源 Model 的 Scheduler Action Get；
3. Action Status 按响应 Element 更新对应 Model；
4. 读取结果保留 Model 维度，再按 Action Owner 规则投影；
5. 不用某一个 Model 的 `scheduleIds` 覆盖其他 Model。

这使 App 能识别同 index 跨模型重复，也能验证“16 个逻辑日程出现第 17 个物理事件”的残留是否已清除。

## 6. 已存在日程的影响

- 不执行一次性全网迁移。
- 已正确位于目标 Owner 的日程不变。
- 位于错误 Model 或两个 Model 同时存在的日程，会在编辑、启停、相关 Group/Space 同步或恢复时执行“清非 Owner、写 Owner”。
- 删除既有日程会清理全部 Model，因此不受历史 Action 影响。

## 7. 边界

- SIG Scheduler Action 本身没有 AUTO；AUTO 语义由 `turnOn` 写入 Light LC Scheduler 所在 Element 实现。
- Dongle collection Scheduler 是独立业务，不参与普通照明 Timed 的多 Model 清理。
- 不新增私有 payload，不改变 0...15 的逻辑日程容量，不修改 Timed 页面交互。
- 编译与契约测试不能替代固件真机执行验证。
