# 场景容量开放：提交审查与 App 测试用例

日期：2026-10-29。审查对象：`a3fa935ee6116e1db3862eee7a8ced2c66370b7f`，分支 `feat/device-scene-261028`。

## 结论与交付

发现 3 项需处理问题：正式 SDK 依赖不具备新 API、地址申请校验失败后无法原页重试、既有同步执行测试无法编译。本轮仅新增测试和本文档，没有修改 App/SDK 业务代码，没有提交 Git。

新增自动化入口：[check_scene_address_request.py](../scripts/check_scene_address_request.py)，夹具：[SceneAddressRequestTests.swift](../Tests/Scene/SceneAddressRequestTests.swift)。测试执行生产地址申请回调及响应校验；HTTP、UI、存储是可控边界。当前 **5 项断言通过、1 项失败**，失败保留为回归证据，不能称为全绿。

以下 App 操作用例均为**待人工执行**。本轮未运行完整 App 构建、Simulator、真机、云端往返或固件验证；已有文档中的历史构建结果没有作为本轮验证结果复述。

## 1. 审查问题

| 编号 | 优先级 | 问题与证据 | 对应用例 |
| --- | --- | --- | --- |
| R1 | P1 | 新增 `Element.observedSceneRegister` 调用依赖本地 SDK 未提交修改；正式 `SunSmart.xcworkspace/xcshareddata/swiftpm/Package.resolved` 仍锁定 `999896766761365d7f01f73839895857c21788d8`，该版本 Element 没有此成员。仅提交 App 无法使正式依赖具备 API；需发布配套 SDK 并使正式解析结果包含它。 | ENV-01 |
| R2 | P2 | 地址池耗尽后，HTTP 成功但缺少有效 `data.provisioner`，校验失败直接返回，`requestedSceneAddresses` 保持 true；再次点击不会重发请求。新增测试执行真实 `requestSceneAddresses()` 复现请求数仍为 1，预期为 2。 | ID-04 |
| R3 | P2 | `check_sync_execution_session.py` 未接入新增 `SceneCapacity` 边界，当前提交报 `cannot find 'SceneCapacity' in scope`，Session/Coordinator 行为测试不能运行。仅在临时组装输入中换回父提交的 `SyncExecutionSession.swift`，其余保持当前文件，两个测试集通过，确认由本次新增调用引入。 | AUTO-01 |

本机 SDK 路径解析为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD 为 `9998967`，存在 Scene Register 等未提交差异；本轮只读使用，未更改。发布配套是已有文档明确列出的待办，仍需作为合入/交付前置条件执行。

## 2. 测试准备与判定口径

- 准备测试 Site 下两个 Space，使用有编辑权限的账号；另备只读账号。不要使用生产照明现场作故障注入。
- Space A：Group A、Group B 各至少一台支持普通 Scene 的灯，另备空 Group C；多 Element/LC 型号及仅 Scene、无 Scheduler 能力型号分别覆盖，不能以单一灯型代替。
- 记录各设备当前普通 Scene Register、场景编号与 Group 关系；另备缺省字段旧项目、待删除场景、32 条场景项目样本。导入前备份，不改固件或服务器配置。
- 先确认 SDK 配套与正式依赖。失败 HTTP 响应、存储失败和迟到回调使用测试替身或已有测试环境，不要求修改线上服务。
- 验证成功分三层：App 意图/本地记录正确；回执状态与 Register 正确；真实 Recall/界面/重启恢复正确。前两层不能替代第三层。
- 除特别注明，以下“保存”同时覆盖自定义场景 DONE、已有场景 SAVE；模板创建另单独执行。错误提示需保留输入，且不得对部分目标偷偷保存。

## 3. App 功能用例

### 3.1 数量、容量与共享入口

| ID | 前置条件 | 操作 | 预期结果 |
| --- | --- | --- | --- |
| CAP-01 | 有足够授权编号，两个空组 | 从 Scenes 新建 17 条以上空场景；再从 Space 连续创建入口添加 | 两入口不以 Space 总数 16 拒绝；列表显示实际数量；默认名称继续递增且不与现有默认名重复 |
| CAP-02 | A、B 各一台灯，Register 已读取 | 将 1～16 关联 A，17～32 关联 B，分别同步并 Recall | Space 有 32 条；每台仅保存自己的 16 条；所有编号和参数保持正确 |
| CAP-03 | A 已占 15 条，B 有空位 | 新场景同时选择 A/B，保存同步；再新增一条同时选择 A/B | 第一次 A 达到 16 成功；第二次整次拒绝、提示 A；B 不留下此次新关系，不能只保存可容纳的组 |
| CAP-04 | A 已满 16 条 | 改已有场景名称、亮度/色温/开关值，保存并同步 | 不因已有 ID 更新误判为第 17 条；物理 Register 不增加编号，Recall 使用新参数 |
| CAP-05 | A 已满；一个旧场景解绑但设备未确认删除 | 尝试关联新场景；完成旧场景清理后再试 | 清理前不释放容量；确认旧 ID 从 Register 消失后允许新增 |
| CAP-06 | 普通 Register 含 App 未建档的残留 ID | 新建/加组触发 Register 读取 | 残留参与容量计算；不创建陌生业务场景、不覆盖现有名称/参数 |
| CAP-07 | 同一 ID 已在目标设备 Register 中 | 将该 ID 的业务场景重新关联目标组 | 不重复计数，符合容量时允许；同 Register 特殊编号不能被当作空位；独立 LC Register 不与普通 Register 混算 |
| CAP-08 | C 为空组，已关联 17 条场景 | Group Members 批量加入两台设备，其中至少一台支持 Scene | 保存前拒绝不合法批次，无部分关系；设备保持原归属。减少到 16 后重试成功 |
| CAP-09 | C 已关联 17 条场景 | 从设备配网/快速添加入口尝试加入 C | 已入网设备不被自动删除；组配置明确失败，不发送超容量场景 Store，也不显示全部配置成功 |
| CAP-10 | 原设备已有场景；备恢复设备 | 执行设备恢复并同步，分别覆盖 16 条、历史超额、Scene-only 设备 | 合法配置可恢复；超额明确失败并保留恢复意图；不能因为没有 Scheduler 跳过 Scene 容量防线 |
| CAP-11 | 历史超额项目或已满设备 | 删除/移除一条关系，再编辑其余已有 ID | 允许减少和不增加占用的编辑，不截断历史数组，不要求先清空全部项目 |

### 3.2 未知状态、异步与重试

| ID | 前置条件 | 操作 | 预期结果 |
| --- | --- | --- | --- |
| ASYNC-01 | 重启 App 或 Mesh 完全断线，观测未知 | 重连后新增目标关系 | 先读取 Register 再复检；已知空允许新增；未知不能按空处理 |
| ASYNC-02 | 读取目标中一台离线 | 模板创建/Scene SAVE/Group Members SAVE，随后恢复设备重试 | 失败时保留输入、没有部分持久化；恢复后可在原流程重试，不永久禁用按钮 |
| ASYNC-03 | Register 读取正在进行 | 退出页面或切 Space，再让旧回调返回 | 不向新 Space 提交旧关系；不创建重复场景；返回原页后可再次操作 |
| ASYNC-04 | 同步前观测未知 | 启动场景同步；分别注入读取成功、读取失败、停止后迟到成功 | 成功读取后发送原任务；失败不发送 Store、不宣称成功；停止后的回调不恢复任务或写错实例 |
| ASYNC-05 | 预检允许，但 Store 返回满容量/目标 ID 缺失 | 同步，然后解除占用重试 | 失败回执不更新为已同步；保留原编号与意图；重试可收敛 |

### 3.3 地址池申请

| ID | 前置条件 | 操作 | 预期结果 |
| --- | --- | --- | --- |
| ID-01 | 现有授权编号已用尽 | 创建下一条场景 | 按 Site 请求 scene 类型 16 个编号，校验并持久化授权后仅创建一次；所有 Space 编号不冲突 |
| ID-02 | 有空闲授权编号，手机无互联网 | 创建空场景 | 不要求申请新地址；允许本地创建。目标设备未知容量的限制仍独立生效 |
| ID-03 | 地址池耗尽 | 断网请求失败，恢复网络后原页重试；请求中连点 | 失败保留名称/图标/选择；恢复后重新请求；同一在途请求不重复发起 |
| ID-04 | 地址池耗尽，响应替身可控 | 首次返回成功但缺少 provisioner，再返回合法完整数据；两次点击创建 | 首次不得创建；第二次必须发出新请求并继续。**当前自动化复现失败：第二次请求被 latch 拦截** |
| ID-05 | 响应替身可控 | 分别返回 lowAddress/highAddress、firstScene/lastScene、整数列表；再测 0、FF00、倒置/重叠范围、缺字段 | 合法格式被接受；非法/不完整分配不污染授权池、不创建场景；错误修复后可重试 |
| ID-06 | 请求在途或授权保存失败 | 切 Space 后返回；另注入保存失败后重试 | 旧响应不提交到新 Space；持久化失败不先建业务场景，后续可恢复；重启后授权池与场景一致 |

### 3.4 删除、兼容与展示

| ID | 前置条件 | 操作 | 预期结果 |
| --- | --- | --- | --- |
| DEL-01 | 空场景，无设备残留、无引用 | 从列表和详情分别删除 | 正常删除，列表/数量/返回页面刷新；未删除错误目标 |
| DEL-02 | 场景在 A/B，B 离线 | 删除后退出、重启，再连接 B 重试 | 失败保留业务记录、编号与清理意图；已确认移除部分不重复当作未完成；全部清理后才释放编号 |
| DEL-03 | 原地址、关联组或组外观测中有该 ID；包含多 Element 设备 | 整体删除；某 Element 返回失败或断线失去观测 | 覆盖实际保存该 ID 的目标；未确认全部清理前不删除业务记录；迟到回调不能作用到重配节点 |
| DEL-04 | Timed/开关仍引用场景，或仍有待同步旧引用 | 尝试删除；修改引用并完成同步后再删除 | 列出引用并拒绝；处理完成后可删；原编号复用后旧控件不能 Recall 新场景 |
| DEL-05 | 场景物理删除成功，存储可注入失败 | 分别使组保存、扩展保存/删除、场景删除失败；恢复后重试 | 不报告成功、不留下不可恢复的部分数据；重开数据库后保留必要重试信息 |
| COMPAT-01 | 旧项目缺少新字段，包含 waitDelete、空数组 | 升级/导入，核对后重启 | 编号、参数、归属、待删除意图保留；未知观测不变为空；不要求重建项目 |
| COMPAT-02 | 32 条场景项目 | 云上传下载、分享导入分别往返，再切换两个 Space | 无 16 条截断，无重复/串号；与原数据逐项核对。离线 Codable 测试不能替代此项 |
| COMPAT-03 | 同 Site 多 Space 仍有可编辑 Space | 部分解绑，再创建场景；另测全部解绑 | 部分解绑不按每 Space 16 条回收共享池，不出现负数；全部解绑沿用剩余地址回收 |
| UI-01 | 英文/简中、长设备名、多个满容量设备 | 查看错误、列表与选场景界面；覆盖 iPhone/iPad | 文案完整国际化、设备可识别、按钮可操作、长内容可读；数量超过 16 后能选择后续场景 |
| AUTH-01 | 只读账号、操作中权限降级 | 进入新增/编辑/删除入口，再尝试提交 | 沿用现有权限限制，不因解限绕过保护；原有场景仍可合法浏览/控制 |

## 4. 自动化与工程验收记录

| ID / 检查 | 本轮结果 | 证据边界 |
| --- | --- | --- |
| ENV-01 正式 workspace / SDK API | 静态确认依赖缺失，未构建 | 发布配套 SDK 后，确认正式解析 revision，再按项目规则验证受影响品牌 generic iOS；不能用本地覆盖证明正式工程可复现 |
| AUTO-01 `python3 scripts/check_sync_execution_session.py` | **编译失败** | 缺少 SceneCapacity；临时使用父提交 Session 输入的对照运行通过，不表示当前提交通过 |
| `python3 scripts/check_scene_address_request.py` | **5 项通过、1 项失败** | 真实生产回调及校验；失败为 ID-04；不访问服务器，不验证真实 UI/持久化 |
| `zsh scripts/check_scene_capacity.sh` | 通过 | 容量边界及本地 SDK Register 策略 |
| `python3 scripts/check_scene_topology.py` | 通过 | 生产候选拓扑、原项编辑、未知/退出状态及分配格式 |
| `python3 scripts/check_scene_deletion_flow.py` | 通过 | 生产删除流程；传输/存储替身，非真实 SQLite 或设备 |
| `python3 scripts/check_scene_register_and_legacy.py` | 通过 | 本地 SDK Register 分支与 Codable 旧字段/32 条往返，非服务端兼容证明 |
| `python3 scripts/check_timed_slot_persistence.py` | 通过 | Timed SQLite 重开/事务及相关 Scene 目标；Scene 容量入口在此夹具中隔离 |
| `zsh scripts/check_scene_delete_capability.sh` | 通过 | 删除能力判定 |
| `zsh scripts/check_fast_add_dual_scene_verification.sh` | 通过 | Fast Add 检查点与双场景验证；不代表配网实机通过 |

合入前最短顺序：先处理 R1～R3并重跑失败检查，再人工执行 CAP-02/03/04、ASYNC-02/04、ID-01/04、DEL-02/04、COMPAT-01/02。其余按受影响设备能力、品牌、权限与 UI 覆盖补齐。
