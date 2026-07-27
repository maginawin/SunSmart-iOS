# Kinetic Switch Proxy 删除事务设计

## 背景

当前 Kinetic Switch 在用户取消 Proxy 并保存时，会先清空 Switch 的当前 Proxy、MAC 和 Security Key，再发送 Mesh 解绑命令。

如果 Proxy 离线或命令失败：

- Proxy 节点实际仍保存原 Switch MAC 和按键配置；
- App 只保留待删除 Proxy 地址；
- Switch 界面显示未绑定；
- App 显示状态与实际 Mesh 状态不一致。

本设计修订已确认的方案 B：Proxy 关联采用“解绑成功后再提交本地删除”的事务语义。

## 目标

1. Proxy 解绑失败时，Switch 继续显示已绑定原 Proxy。
2. 保留重试解绑所需的 Proxy、MAC 和 Security Key。
3. Proxy 解绑成功后，才清除本地有效关联。
4. 删除整个 Switch 时，只要必要的 Proxy 或组清理失败，就保留 Switch 对象。
5. 用户从 Space 删除或强制删除 Proxy 节点时，直接清除所有 Switch 对该节点的引用。
6. 同一 Proxy 不得在一个同步事务内同时执行解绑和重新绑定。
7. App 重启后仍能识别并重试未完成的 Proxy 删除。
8. 从 Group Members 移除 Proxy 节点时，Proxy 清理成功后才能执行真实组退订。

## 非目标

- 不新增通用设备事务框架。
- 不修改 NordicSigMeshSDK 的 EnOcean 消息实现。
- 不调整与 Kinetic Switch 无关的设备删除流程。
- 不重构现有 Switch 数据库存储结构。
- 不新增独立的 Proxy 状态枚举或数据库迁移。
- 除 Group Members 移除 Proxy 的确认提示外，不新增其他用户可见文案。

## 状态字段语义

继续使用现有字段，但明确其职责：

- `proxyNodeAddress`：当前仍被视为有效的 Proxy，或者 Proxy 替换流程中的目标 Proxy。
- `deleteProxyNodeAddress`：需要先完成解绑或清除的旧 Proxy。
- `enOceanMacAddress`：当前 Kinetic Switch MAC。
- `enOceanSecurityKey`：当前 Kinetic Switch Security Key。

### 稳定绑定

- 当前 Proxy：L1
- 待删除 Proxy：空
- MAC、Key：保留

### 当前 Proxy 待解绑或解绑失败

- 当前 Proxy：L1
- 待删除 Proxy：L1
- MAC、Key：保留

该状态表示：

- 实际 Mesh 状态仍按“绑定 L1”处理；
- 用户意图是删除 L1 关联；
- UI 显示已绑定 L1，同时显示同步失败或待同步状态；
- 同步规划只生成 L1 解绑任务。

### Proxy 替换

如果用户把 Proxy 从 L1 更换为 L2：

- 当前 Proxy：L2
- 待删除 Proxy：L1
- MAC、Key：保存目标绑定数据

同步顺序必须是：

1. 解绑 L1；
2. L1 解绑成功后绑定 L2。

如果 L1 解绑失败，不得继续绑定 L2。

### 已解绑

- 当前 Proxy：空
- 待删除 Proxy：空
- MAC、Key：空

只有 Proxy 解绑成功，或当前 Proxy 节点已经从 Space 删除时，才能进入此状态。

## 用户取消 Proxy 的数据流

1. 用户在编辑副本中关闭 L1。
2. 保存时识别到原始 Switch 仍绑定 L1，而编辑副本要求删除。
3. 在进入同步前：
   - 将 L1 写入 `deleteProxyNodeAddress`；
   - 保留原始 `proxyNodeAddress`；
   - 保留原始 MAC 和 Security Key；
   - 保存该待删除状态，使 App 重启后仍可恢复。
4. 同步规划检测到当前 Proxy 与待删除 Proxy 是同一地址：
   - 只生成 Proxy 解绑任务；
   - 不生成 Proxy 绑定任务。
5. 解绑成功：
   - 清除当前 Proxy；
   - 清除待删除 Proxy；
   - 清除 MAC 和 Security Key；
   - 保存 Switch；
   - UI 更新为未绑定。
6. 解绑失败：
   - 不清除任何 Proxy 关联字段；
   - Switch 保持已绑定 L1；
   - UI 显示同步失败并允许重试。

## 删除整个 Switch 的数据流

1. 删除计划包含：
   - 当前绑定组；
   - 待解绑组；
   - 当前 Proxy；
   - 待删除 Proxy。
2. Proxy 与组清理任务按依赖顺序执行。
3. 任一必要任务失败：
   - 不删除本地 Switch 对象；
   - 已失败的 Proxy 保留完整关联信息；
   - 已成功任务按真实结果更新本地状态；
   - 用户可以重新同步剩余任务。
4. 所有必要任务成功后：
   - 删除本地 Switch 对象；
   - 删除 Switch 的虚拟通讯组；
   - 清理对应本地缓存。

## 从 Space 删除 Proxy

设备从 Space 正常删除或强制删除时，节点已经不再是可重试的 Mesh 管理对象，因此节点删除是本地 Proxy 关联清理的明确终点。

节点删除扩展清理需要检查所有 Switch，而不是只处理第一个匹配对象：

- `proxyNodeAddress` 指向被删除节点：
  - 清除当前 Proxy；
  - 清除 MAC；
  - 清除 Security Key。
- `deleteProxyNodeAddress` 指向被删除节点：
  - 清除待删除 Proxy。
- 当前 Proxy 与待删除 Proxy 都指向被删除节点：
  - 清除以上全部字段。
- 当前 Proxy 指向其他节点、只有待删除 Proxy 指向被删除节点：
  - 只清除待删除 Proxy；
  - 保留当前目标 Proxy、MAC 和 Key。

所有受影响的 Switch 都需要保存，并触发 Switch 与 Space 数据刷新。

## 从 Group Members 移除 Proxy

从 Group Members 移除节点不等同于从 Space 删除节点：

- 节点仍然存在于 Mesh 网络；
- 节点仍可重新同步；
- Proxy 解绑失败时，节点仍保存原 Switch MAC 和按键配置；
- 因此不能直接清除本地 Switch 关联，也不能在 Proxy 清理失败后继续完成真实组退订。

### 前置检测与确认

用户保存 Group Members 变更时，在修改持久化状态和进入同步页面前，检查所有待退出节点是否满足以下任一条件：

- 被任一 Switch 的 `proxyNodeAddress` 引用；
- 被任一 Switch 的 `deleteProxyNodeAddress` 引用。

检测范围应覆盖与当前组存在绑定或待解绑关系的 Switch，并兼容历史异常数据中一个节点被多个 Switch 引用的情况。

如果存在受影响的 Switch，显示一次确认提示：

- English：`One or more selected devices are being used as switch proxies. Removing them from the group will also unbind the corresponding switch proxies.`
- 简体中文：`一个或多个所选设备正在作为开关代理。从组中移除这些设备也会解除对应的开关代理绑定。`
- 操作：复用现有 `Cancel` 和 `Continue`。

用户取消：

- 不修改节点退组状态；
- 不修改任何 Switch Proxy 字段；
- 留在 Group Members 页面。

用户继续后才创建复合事务。

### 未完成 Proxy 事务冲突

一个 Switch 只有一个 `deleteProxyNodeAddress`，因此不得用新的待删除地址覆盖尚未完成的旧 Proxy 清理。

保存 Group Members 变更前需要执行原子预检：

- 当前 Proxy 是待退出节点，待删除 Proxy 为空或与当前 Proxy 相同：允许进入本次复合事务。
- 待退出节点仅作为待删除 Proxy，当前 Proxy 指向其他节点：复用现有待删除任务，不覆盖地址。
- 当前 Proxy 是待退出节点，但待删除 Proxy 指向另一个节点：阻止本次 Group Members 保存，复用现有 Proxy 未清理提示，引导用户先完成已有同步。
- 多个待退出节点中任意一个存在上述冲突：整次保存不产生任何节点或 Switch 状态变更。

### 复合事务

对每个作为 Switch Proxy 的待退出节点：

1. 保留当前 Proxy、MAC 和 Security Key。
2. 将节点地址写入对应 Switch 的 `deleteProxyNodeAddress`。
3. 保存 Switch 的待删除状态。
4. 按以下顺序执行：
   - 删除节点上的 Kinetic Switch Proxy 配置；
   - 删除节点对相关 Switch 虚拟通讯组的订阅；
   - 执行其他组配置清理；
   - 最后从真实 Group 退订。

真实 Group 退订必须依赖所有相关 Proxy 和 Switch 虚拟组清理任务成功。

如果一个节点被多个异常 Switch 数据引用：

- 为所有引用建立清理任务；
- 任一必要清理失败，都不得执行真实 Group 退订；
- 只提交已经由 Mesh 成功确认的局部结果。

### 失败与部分成功

Proxy 清理失败：

- 不执行真实 Group 退订；
- 节点继续保留在原 Group；
- 失败 Switch 继续保留当前 Proxy、MAC、Key 和待删除地址；
- Group 和 Switch 均保持待同步或同步失败状态；
- 用户可以重新同步。

Proxy 清理成功、真实 Group 退订失败：

- Switch Proxy 关联按成功结果清除；
- 节点继续保留在原 Group；
- 只保留真实组退订及其他未完成任务用于重试。

全部任务成功：

- Switch Proxy 关联清除；
- 节点退出 Group；
- Group Members 与 Switch 页面分别刷新为最新状态。

待退出节点不是任何 Switch 的当前或待删除 Proxy 时，沿用普通 Group Members 退组流程。

## 同步规划规则

### 同地址待删除

当当前 Proxy 与待删除 Proxy 地址相同：

- 生成一个 Proxy 解绑任务；
- 不生成 Proxy 绑定任务；
- 解绑失败时保留当前关联；
- 解绑成功时清除全部关联字段。

### 不同地址替换

当当前 Proxy 与待删除 Proxy 地址不同：

- 先执行旧 Proxy 解绑；
- 旧 Proxy 解绑成功后，才允许执行新 Proxy 绑定；
- 旧 Proxy 解绑失败时，新 Proxy 绑定任务应跳过或保持等待，不能继续发送。

### 删除整个 Switch

- 当前 Proxy 与待删除 Proxy 合并去重；
- 每个实际仍保存 EnOcean 绑定信息的 Proxy 都需要进入删除计划；
- 只有所有必要清理成功后才触发本地 Switch 删除回调。

## UI 规则

- 稳定绑定：显示已绑定 Proxy。
- 待解绑或解绑失败：仍显示已绑定原 Proxy，同时沿用现有同步失败标识和重试入口。
- 解绑成功：显示未绑定。
- Space 删除 Proxy：Switch 立即显示未绑定。
- Group Members 移除 Proxy：先显示已确认的影响提示；用户继续后才修改待同步状态。
- 除上述确认提示外，不新增用户可见文案，优先复用现有同步失败和重新同步交互。

## 错误处理

- Mesh 命令失败或超时不得清除有效 Proxy 信息。
- 用户退出同步页面不得回滚成未绑定状态。
- App 在待解绑状态退出并重新启动后，应仍显示已绑定 Proxy和待同步状态。
- 部分任务成功时，本地状态只提交已经由 Mesh 成功确认的部分。
- 强制删除 Space 节点不等待 Proxy 解绑，但必须完成本地引用清理。
- Group Members 移除 Proxy 时，Proxy 清理失败必须阻止真实 Group 退订。
- 用户取消 Group Members 的影响提示时，不得产生任何待删除或待退组状态。

## 测试设计

### 聚焦策略测试

1. 当前 Proxy 与待删除 Proxy 相同，只生成删除目标。
2. 同地址待删除时，不生成绑定目标。
3. 当前 Proxy 与待删除 Proxy 不同，删除旧 Proxy、绑定新 Proxy。
4. 旧 Proxy 删除失败时，不允许执行新 Proxy 绑定。
5. Proxy 删除失败后，当前 Proxy、MAC、Key 和待删除地址全部保留。
6. Proxy 删除成功后，当前 Proxy、MAC、Key 和待删除地址全部清空。
7. Space 删除当前 Proxy，清除完整关联。
8. Space 删除仅作为待删除 Proxy 的节点，只清除待删除地址。
9. 一个节点被多个异常 Switch 数据引用时，清理所有引用。
10. Group Members 移除 Proxy 时，Proxy 删除任务先于真实 Group 退订。
11. Group Members 的 Proxy 删除失败时，真实 Group 退订被跳过。
12. Group Members 的 Proxy 删除成功、真实 Group 退订失败时，只保留剩余退组任务。
13. 用户取消 Group Members 的影响提示时，不修改节点或 Switch 状态。
14. 当前 Proxy 与已有待删除 Proxy 地址冲突时，阻止 Group Members 保存且不覆盖旧地址。
15. 批量移除中任一 Proxy 存在未完成事务冲突时，整批操作不产生状态变更。

### 回归场景

1. L1 在线，正常绑定、解绑成功。
2. L1 离线，解绑失败，返回后仍显示绑定 L1。
3. App 重启后仍显示绑定 L1 和同步失败状态。
4. L1 上线后重新同步，成功解绑并更新为未绑定。
5. 删除整个 Switch 时 L1 离线，Switch 对象和 Proxy 信息保留。
6. L1 上线后重试删除，清理成功后才删除 Switch。
7. L1 离线时从 Space 强制删除，Switch 立即清除 L1 关联。
8. L1 被删除后，原 Kinetic Switch 可以使用其他 Proxy 正常绑定。
9. L1 替换为 L2 时，验证先删除 L1、后绑定 L2。
10. 从 Group Members 移除 L1，确认后先解除 Proxy，再退出 Group。
11. 从 Group Members 移除离线 L1，Proxy 解绑失败后 L1 仍在 Group，Switch 仍显示绑定 L1。
12. L1 恢复在线后重试 Group 同步，完成 Proxy 清理和退组。
13. 在 Group Members 影响提示中取消，节点选择和 Switch 关联保持不变。
14. 历史异常数据中 L1 被多个 Switch 引用时，任一清理失败都阻止 L1 退组。
15. Switch 正在从 L1 切换到 L2 时尝试从 Group Members 移除 L2，操作被阻止且 L1 的待删除信息不丢失。
16. 批量移除多个节点时，其中一个 Proxy 存在未完成事务冲突，其他节点也不提前进入待退组状态。

### 工程验证

- 聚焦 Swift 策略测试。
- `SunSmart.xcodeproj/project.pbxproj` 结构校验。
- `git diff --check`。
- SunSmart、Archipelago、SLG Sync Plus、SylSmart 的 generic iPhoneOS Debug 构建。
- 真机 Mesh 验收与编译验证分别报告。

## 验收标准

满足以下条件即视为完成：

1. Proxy 解绑失败后，UI、持久化数据和实际 Mesh 状态都保持“绑定原 Proxy”。
2. 失败状态可以跨页面和 App 重启重试。
3. 解绑成功后才显示未绑定。
4. Space 删除 Proxy 后不会留下 Switch 对该节点的当前或待删除引用。
5. 删除整个 Switch 不会在 Proxy 或组清理失败时误删本地对象。
6. Proxy 替换不会在旧 Proxy 解绑失败时继续绑定新 Proxy。
7. Group Members 移除 Proxy 时，Proxy 清理失败不会导致节点退出真实 Group。
8. 用户取消 Group Members 的影响提示时，不产生任何状态变更。
9. Group Members 操作不会覆盖不同地址的已有待删除 Proxy。
10. 四个品牌 target 编译通过，且没有修改 NordicSigMeshSDK。
