# Site Trigger Zone 阶段三：Save 后跨 Space 同步流程修订方案

日期：2026-09-14。状态：**三项边界已获用户回复，按文末确认记录修订；实物协议关卡仍待执行。仅分析与规划，未修改业务代码、SDK、云数据或设备配置。** 本文承接 [阶段三初版方案](260914_1455_site_trigger_zone_stage3_development_plan.md)，以本次用户确认和补充覆盖初版中冲突的 Save/Sync 交互与退出 Key 策略。

## 本轮明确的需求

1. 优先验证并复用现有 Site Primary AppKey，不预先新建专用 Key；实物协议验证通过后才开发设备写入，完整验收前不开放正式设备同步入口。
2. Save 成功后**自动跳转** `Sync device(s)` 页面，计算并执行 `Remove`、`Configuration`；这替代初版“Save 后由用户另点 Sync”的建议。云保存成功和设备同步完成仍是两个独立结果。
3. 按 Site Trigger Zone 的 Space 顺序，逐个 Space 连接、执行其 `Remove` 后执行其 `Configuration`，再切到下一个 Space；不能先集中执行全部 Space 的 `Remove`，再回头执行全部 `Configuration`。
4. “连接到 Space”采用**临时执行步骤**，在页面可见当前连接状态和失败原因，但不作为可勾选的持久设备任务，也不计入 `x/y done`。同步计划与回执仍持久保存。
5. **以 Space 为单位决定转发 AppKey。** 若 Space 中没有任何设备已安装该 Site 的 Primary AppKey，且该 Space 尚不参与需启用的 Site Zone，则现有 Group Path、Group Trigger Zone、Space Trigger Zone 继续使用 Space AppKey；若 Space 中任一设备已安装 Primary AppKey，或本次 Site Zone 使它需要部署 Primary AppKey，则该 Space 内上述**全部邻近照明关系**改以 Primary AppKey 为目标。缺少 Primary NetKey/AppKey/相关 Model Bind 的关系设备生成 `Configuration` 前置子任务，即使不是 Site Zone 成员。删除 Site Zone 后不撤已安装 Primary Key；只要 Space 中仍有任一设备持有它，正常 Space 编辑继续使用 Primary AppKey。
6. 同步结束有任何失败或被连接失败阻断的任务，显示底部失败提示并保留可重试项；Figma 的通信范围文案可作为提示内容，但不能代替实际失败原因。

## Figma 结构化信息与复用边界

- [进行中，635:6950](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=635-6950)：节点名 `Screen / Sync Devices / In Progress`；面板包含 `STOP`、`Sync device(s)`、`Remove`、`Configuration`、`2/3 done`、`Select all`。画面基于单个 `Space 1` 背景，并未规定跨 Space 连接或命令排序。
- [部分失败，635:7002](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=635-7002)：节点名 `Screen / Sync Devices / Partial Failure`；包含 `RE-Sync` 和底部 `Toast / Sync Retry Guidance`，原文为 “If the failure rate is high in a space, move to the communication range of that space and try synchronizing again.” 原型没有“high”的数值阈值，也没有说明权限/容量/设备不支持时的提示。

采用现有 UIKit `SyncDevicesViewController` 的任务行和操作模式，但以 Site 专用执行计划覆盖其当前全局 `Remove → Configuration` 排序。UI 顶层按 Space 分区，每个分区展示 `Remove` 和 `Configuration`；底部只出现一次全局完成提示。英文文案用 Figma 正确拼写 `failure rate`，新增文案同步简体中文。

## 完整操作流程

### 1. Save 与启动边界

按下 Zone 的 Save 后，先维持阶段二的云端完整 `extensionData` 提交及 GET 回读。仅云端目标确认、无冲突且本次 Zone 身份仍有效时，冻结目标版本、旧/新成员快照与拓扑依赖，进行设备预检，然后进入同步页并自动开始。网络失败、回读未确认、权限丢失或页面已切 Zone 时不发送设备命令；保持草稿或 pending，并在原页面说明原因。重进页面的设备待同步图标继续提供同一个同步页入口，不再次要求改动云数据。

云确认与设备结果必须用两套状态记录；跳转前先持久化按 Space、设备、`Remove`/`Configuration` 分开的目标任务，成功、失败、未知和阻断由设备回执单独更新。Space Trigger Zone 的实际本地先行流程及 Site 所需任务账本见 [Save 与同步顺序分析](260914_1532_space_site_trigger_zone_save_sync_order_analysis.md)。

若云保存成功但设备计划不可执行（缺失 Space、权限/占用、Key/Bind 能力、地址歧义或邻居容量），仍进入同步页显示分 Space 阻断原因与待同步状态，**不发送任何业务命令**。若计划确实无差异，进入同步页显示 `No devices need syncing` 并可返回，不制造空任务或错误成功回执。空 Zone 且无旧设备清理时仍保持既有云保存完成流程，无需弹出空同步页。

当前同一个 `saveZone` 还被“切 Zone/退出时未保存提示”的 Save 调用，并在云确认后继续原导航动作。**用户已确认**新自动跳转仅适用于 Zone 操作栏的 Save：弹窗中的 Save 继续完成云保存并执行原本的切换/退出，设备待同步状态保留，之后从 Sync 图标进入。这保持阶段二 Save/Discard/Cancel 的导航语义。

### 2. 计划顺序与任务语义

Space 顺序以当前已云确认 Zone 的成员数组首次出现顺序为主，与 Site Zone 页面展示顺序一致；只在旧版本有成员、现在需要清理的 Space 沿用旧成员中的相对顺序追加。若其他 Site Zone/共享设备使**实际写入范围**增加未出现在本 Zone 的 Space，按 Site 的稳定 Space 顺序追加并标明来源；全部纳入权限与连接预检。整个运行只冻结一次顺序，执行中列表刷新不重新排序。单个 Space 的 Primary 策略扩展到该 Space 内所有 Group Path、Group Trigger Zone、Space Trigger Zone，不能仅按 Site Zone 成员筛选同步对象。

每个 Space 使用如下流水线：`临时 Connect/复用连接 → 校验 Mesh UUID、NetKey、传输 AppKey、权限和目标版本 → Remove → Configuration → 固化本 Space 回执 → 下一 Space`。每个 Space 最多一次主动连接/离开；只有连接实际失效或用户明确 Retry 才重新连接。`Remove` 是从旧、新**完整合并目标**导出的过时设备关系清理，不等于移除 Group、清空整张邻居表、删除 Primary Key 或撤销其他 Path/Zone 贡献。`Configuration` 包含缺失 Primary NetKey/AppKey/Model Bind、转发 Key、TTL、Enable/Relay/合并邻居；任务即使不属于 Site Zone 成员，只要其最终目标需要改变也要显示，来源可标 `Group Path`/`Group Trigger Zone`/`Space Trigger Zone`。同一设备只生成一个最终目标，必要步骤按依赖排序，不因它同时出现在 Remove 和 Configuration 而写两份相互矛盾的终态。Space 是否已有 Primary AppKey 必须核对**该 Site 的明确 AppKey 身份及其 Primary NetKey 绑定**，不可只看 Primary NetKey、读取 SDK 有兜底行为的 `mainApplicationKey` getter，或从当前页面上下文推测。Key 清单不完整时状态为未知并阻止误判为“该 Space 无 Primary”。

进度按**可执行的设备任务行**统计：同一设备的 Remove、Configuration 各算一行；Key/Bind 等前置命令作为 Configuration 的步骤，不增加进度分母；临时连接不计数。连接失败时本 Space 未发送的任务标为 `Blocked by connection`，保留待重试，不冒充设备 ACK 失败；按依赖规则决定下一 Space 能否执行，不跳过前置条件强行配置。STOP 停止后续命令与 Space 切换，已在途结果仍写回其原 operationId。

### 3. 首次部署的一个关键取舍

“所有跨 Space 接收端先具备 Primary Key/Bind，再激活统一转发”与“首次同步每个 Space 只连接一次并立即完成 Remove/Configuration”在尚未部署 Key 的设备上**不能同时严格保证**。A Space 完成后 B Space 尚未连接，A→B 可能暂时不通；若 B 后续连接失败，会形成可恢复的部分生效。Group Path 整条同 Key 的约束则必须在**每个 Space 内**按整条受影响 Path 的设备完成 Key/Bind 后，才切换该 Path 的转发 Key。

建议以用户要求的一次 Space 访问为主：同步前全量预检，逐 Space 先完成本 Space **所有受影响 Path/Zone 设备**的 Key/Bind，再执行本 Space 的 Remove/Configuration；跨 Space 联动在所有相关 Space 完成前始终标 `partially applied`，绝不报整体成功。用户补充明确：相关设备的 Primary Key/Bind 未完成时，Group Path、Group Trigger Zone、Space Trigger Zone 均必须显示需要同步。这是目标状态与 UI 规则，**不等于**过渡期间现场已经安全。若 3A 实物验证证明过渡状态会破坏原 Path/Zone，则本次同步应拒绝一遍部署，改为“全 Space 预部署 → 全 Space 激活”两轮连接，或要求设备预先部署 Key；不能靠 UI 状态隐藏这种冲突。

### 4. 失败、提示与重试

运行结束只要有失败、被阻断或结果未知的任务，就展示底部提示，保留对应 Space 和设备步骤。底部主信息给出失败/待重试数量；若存在通信类失败，可附 Figma 的条件性范围建议，避免把权限不足、容量超限、固件不支持误导成距离问题。无需人为设“高失败率”阈值，因为原文是条件句；单台失败也可显示该建议，但详情必须列出真实原因。失败 Space 的后续任务保持 pending/blocked；可独立继续执行无依赖的 Space，不跨越未满足的共享 Key/拓扑依赖。重试只选择失败/阻断/未知项，却必须自动带上仍缺失的前置步骤；已成功且目标指纹未变的命令不重复发送。旧运行的迟到 ACK 不得清除新版本 pending。

## 对原阶段三增量的调整

| 增量 | 本轮修订后的交付 |
| --- | --- |
| 3A 实物可行性 | 增加首次单遍部署的过渡状态与失败后原 Group Path/Zone 是否正常的验证；确认现有 Primary Key/Bind/固件容量及两个 Figma 状态的交互含义。 |
| 3B 合并目标 | 先判定 Space 级 Primary 模式，再汇总该 Space 所有 Group Path、Group Trigger Zone、Space Trigger Zone；非 Site 成员也可能成为 Key/Bind 任务。确认 Space 显示顺序、旧成员清理 Space 和额外写入 Space 的排序与权限。 |
| 3C SDK 与账本 | 显式区分传输 Key/目标转发 Key；加入 Space 会话执行器及一次访问内的 Remove→Configuration 依赖图。连接是临时步骤，任务和回执持久化。 |
| 3D 同步 UI | 云确认后自动进入同步页并自动运行；按 Space 分区、状态可见但连接不计进度；失败后底部提示、选择重试。原同步页的全局 `Remove→Configuration` 顺序不能直接复用。 |
| 3E 回归 | Site 删除后，只要该 Space 仍有任一设备持有 Primary AppKey，普通 Group Path/Group/Space Zone Save 继续使用 Primary 转发策略；测试首次迁移中断、跨 Space Proxy 切换、旧版本 ACK、STOP、Restore、Kinetic、五品牌 target。 |

## 用户确认记录与实施解释

1. **Primary 范围已确认改为 Space 级。** 不能再使用“仅曾与 Site Zone 相交的关系闭包”作为 Key 作用域。一台设备已持有该 Site Primary AppKey，就使该 Space 的全部 Group Path、Group Trigger Zone、Space Trigger Zone 以 Primary 为转发目标。无任何设备持有且无新的 Site 关联时，保留原 Space Key 行为。Site Zone 首次覆盖原本无 Primary 的 Space 时，计划必须先把本次要部署 Primary 的意图纳入 Space 模式判断，避免第一台设备绑定成功后执行中途才改变其余目标；整次计划固定模式和版本，失败后按最新明确状态重新规划。
2. **未完成绑定 = 需要同步。** 任何受上述关系约束的设备缺少目标 Primary NetKey/AppKey/Model Bind，或者转发 Key 与最终目标不符，均生成任务，并让所属 Path/Zone 显示需要同步；旧同步成功回执不能掩盖单独的 Key/Bind 差异。第 3A 关卡仍需验证一次 Space 访问的过渡影响，用户此次回复没有将“标记待同步”等同于“过渡期联动已安全”。
3. **两种 Save 入口已确认区分。** Zone 操作栏 Save 在云端确认后自动进入同步页；切 Zone/退出未保存弹窗里的 Save 在云端确认后继续原导航，设备任务保持待同步，之后由 Sync 图标恢复。

需要在 3A 只读盘点中特别检查已因其他功能持有 Site Primary AppKey 的设备，因为按“任一设备”规则，它们也会使所在 Space 的邻近照明关系整体转向 Primary。设备列表缺失、仅知道 Primary NetKey、或 AppKey 身份未核实均不应默认为“无 Primary”。
