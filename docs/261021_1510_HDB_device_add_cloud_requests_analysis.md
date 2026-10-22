# HDB 添加一个设备时的云请求分析

首次分析：2026-10-21；最近实施：2026-10-22。已按确认方案修改 App，并完成受控回归及 SunSmart generic iOS Debug 构建；2026-10-22 新现场日志进一步确认本次双设备成功路径达到批次同步目标。最新现场分析与实施结果见下文。后续保留实施前复核、计划和原始日志分析，历史请求数不能替代新版本现场验收。

## 2026-10-22 现场双设备日志验收

### 结论

**本次“连续点选两台设备、同批成功完成”的现场路径修复成功：共 4 次实际 HTTPS，其中设备配置同步只有 3 次，全部发生在整批 HDB 任务完成之后；另 1 次为独立 Space 心跳。** 未发现逐设备/逐 ACK 上传、添加期间反复读取配置、重复最终上传或回读重试。最终不仅 HTTP 200，而且有 `SpaceConfigurationReadback stage=confirmed` 和 `CloudSync Success`。

证据文件：[adding devices.txt](</Users/maginawin/Desktop/adding devices.txt>)，2137 行，261099 字节，SHA-256 `03971089a383552459abb52cd63df16bef4292228a7a20b795ca480ae672d3fe`。分析时 App HEAD 为 `69c6ed90`，工作树仍含本任务未提交修复；日志有新增 AddBatch 标记，与修复行为一致，但没有 App 构建 revision，不能单凭日志独立证明具体安装产物。此轮仅分析日志和代码、更新本文，没有修改业务代码或重新构建。

### 全部 HTTPS 请求

所有请求使用 **POST**，共同 HTTPS 前缀为 `https://www.mericher.com/srv2`。按 `[HTTP][Request]` 计数，再由 Response 和 task 11～14 的 Metrics 交叉验证。每个 task 的零字节与非零字节 Metrics 是同一请求的观测，不能重复计数；`CloudSync Request` 也不是第五个 HTTP。

| 序号 / task | 请求行 / 响应行 | target / 路径（省略共同前缀） | 所处流程与作用 | 结果与判断 |
| --- | --- | --- | --- | --- |
| 1 / 11 | 141 / 155 | `heartbeat`，`/sitespace/user/hb` | 第 3 行批次开始后，仍在标准 Mesh Model AppKey 绑定阶段；周围有 `ConfigModelAppStatus` 与后续绑定消息。上报当前用户在 Site/Space 中的在线状态及角色，错误返回可触发权限处理 | HTTP 200；响应体 2 字节，businessCode 未提供。它没有读取/上传设备配置，是独立心跳，符合本次保留非配置请求的范围 |
| 2 / 12 | 2033 / 2045 | `spaceInfo`，`/sitespace/get/spaceprops` | 第 2030 行批次结束后；2032 行明确为 `baselineRequest`。最终上传前读取当前远端基线，校验权限、成员/配置变化，避免用旧本地快照覆盖远端变化 | HTTP 200；2055 行 `noPendingReceipt`，说明当前不是旧提交回读重试。保留这一次前读 |
| 3 / 13 | 2073 / 2085 | `siteUpload`，`/sitespace/sync/siteprops` | 前读完成并完成本地清理/导出后，统一上传 Site 和当前 Space。2069 行 `operation=syncSite syncSpaceCount=1`，这里只有一个 Space，不能误读成只上传一台设备 | HTTP 200，businessCode=200，businessMessage=success；唯一配置上传，包含本批最终 Space 快照及 Site 地址资源 |
| 4 / 14 | 2097 / 2109 | `spaceInfo`，`/sitespace/get/spaceprops` | 上传响应成功后，2096 行为 `stage=request`，用于验证刚提交的快照确实进入云端 | HTTP 200；2119 行 `confirmed`，2120 行 `CloudSync Success`。保留这一次回读，与前读目的不同 |

没有 `spaceUpload`、第二次 `siteUpload`、地址申请或首次 Site 创建请求。两次 `spaceInfo` 分别属于上传前与上传后，不是重复进入 Add Device 页面读取。原始 HTTP 日志没有逐请求开始/结束时间戳，因此此处按行序与阶段标记定位，不把数据版本号当作 HTTP 时间计算。

代码对照：`SpaceViewController.startHeartbeatTimer` 每 30 秒调度心跳并首次立即 fire；`heartbeatRequest` 处理权限撤销、未授权、密码失效等返回。日志只证明观察到了 1 次心跳，不能辨别它究竟是首次 fire 还是该周期 timer 触发，更不能据这一条推断需要取消心跳。`SpaceConfigurationSafety.resumeUpload` 的 `baselineRequest` / `noPendingReceipt` / `confirmed` 与本次三个同步请求一一对应。

### 添加与同步的完整顺序

1. **第 1～6 行：点选两台设备。** 第 2、6 行各有一次添加按钮操作；第 3 行只登记一次 `AddBatch begin`。随后两台设备均报告 3 个 Elements，并在第 17、27 行报告配网成功。后续主地址为 `0x0008` 和 `0x000B`。
2. **第 28～1357 行：标准 Mesh 配置。** 在 Model 绑定、订阅及标准默认配置期间，唯一 HTTPS 为 task 11 心跳。没有 Space 基线读取或配置上传。
3. **第 1358～2027 行：HDB 准备和配置。** `summary-saved` 后 `start count=2 incomplete=0`。每台都有 4 个 subscription、1 个 publication、1 个 initialization 任务的 `persisted`；初始化各为 `handles=12 ack=12`，每台合计 17 个成功 ACK，两台共 12 个 HDB 任务、34 个 ACK。这里只统计 HDB DeviceTask，不把前面的标准配置/SDK 重复打印也算进去。所有落盘日志 `reason=none`，过程中没有配置 HTTPS。
4. **第 2028～2030 行：唯一整批收尾。** `settled-success count=2 incomplete=0` → `finished count=2 incomplete=0` → `AddBatch finish nodes=2 queued=0`。这时两台都结束，才进入云同步。
5. **第 2031～2123 行：唯一同步轮次。** baseline 前读 → 本地检查/导出 → Site＋Space 上传 → 回读 confirmed → CloudSync Success；没有第二轮提交或重试。
6. **第 2124～2137 行：设备状态读取。** `LightCTLGet` / `LightCTLStatus` 是 Bluetooth Mesh 消息，用于获取灯状态，属于 BLE 通讯，不是 HTTPS；日志中没有随后追加云上传。日志尾部很短，不能据此宣称长时间停留或退出页面均已验收。

### 附带日志及成本

| 项目 | 本次证据 | 对结论的影响 |
| --- | --- | --- |
| 本地导出 3 次 | 2056～2067 行，共 3 组 `export begin/end`，均 `main=true`；各约 22 ms，合计约 67.08 ms | 这些是本地工作，不是 3 次额外网络请求。与 cleanup 的导出前检查、持久状态复核及最终请求导出相符；现有日志未标调用栈，不能逐次作运行调用点断言。可另评估 CPU/I/O 合并，本轮不因此判为网络修复失败，也不能据这份日志断言出现了可感知卡顿 |
| 响应传输量 | 4 次 task 非零 Metrics 的 `receivedBytes` 合计 17309；两次 Space 读取合计 17242；Space 解码后合计 124544 字节 | Metrics 观测值，不是包含所有链路开销的精确抓包总量。`siteUpload` 请求 body 为 12574 字节并声明 gzip |
| Mesh 查询超时 | 1396 行 `start currentActiveDistribution, timeout: 3.0`，1607 行 `currentActiveDistribution timeout` | 是 Mesh 固件分发状态查询，没有对应 HTTPS。后续 HDB 任务落盘与云回读都成功，未阻断本次目标；日志不足以证明该查询超时的底层原因，此轮未扩大修复范围 |
| 本地 Model 未绑定警告 | 如 2024～2025、2137 行 `Local ... not bound to key` | SDK AccessLayer 在向手机本地 Model 分派收到的消息时打印；不是直接证明远端设备 AppKey 绑定失败。本次远端 HDB ACK 和终态成功需独立依据 DeviceTask / Add 标记判断 |
| AVAudioSession 提示 | 第 4、7 行提示在主线程调用可能影响响应 | 与音频会话调用有关，不是 HTTPS 失败或配置重复同步；日志没有 UI 耗时证据，不据此判定卡顿根因 |

### 验收判断与剩余边界

本次已由现场日志确认：**双设备共用一个批次、添加中途不读写远端配置、多次本地 ACK 保存不会放大 HTTP、统一一次上传且回读确认成功。** 这是本次请求数量优化的成功证据，不能再仅称为“受控测试目标”。

仍未由本日志覆盖：同页面完成后再添加下一批、在 HDB 收尾期间追加设备、部分失败/全失败、取消/页面销毁、断网恢复、账号或权限变化、历史待确认提交及首次 Site 恢复、长时间停留/退出后是否无重复同步。也没有足够信息把现场记录归到两个添加模式各自的完整验收。原来的自动化回归可证明相应受控行为，不能替代这些场景的现场测试。

历史日志是单台设备的 18 次配置 HTTP，本日志是双台同批的 3 次配置 HTTP＋1 次心跳；可以确认请求已按批次收敛，但场景和采样窗口不同，不据此直接给出端到端提速比例。

## 2026-10-22 实施结果

### 已实现行为

- Classic / Professional 共用 `HDBDeviceAddBatch`。第一台 HDB 设备实际配网前登记账户、区域、Site、Space、Mesh 身份；节点入网后及时持久化 Space 摘要及 Site 地址版本。标准配置和 HDB 的每次本地保存继续执行，批次只推迟云调度。
- HDB 配置只处理本次 FastAdd 成功列表对应的当前节点，并核对本批实际配网 UUID；页面累计结果仍保留。相同地址出现新节点时替换累计列表中的旧实例，避免把旧 UUID 用作本次结果。旧批 Session 的迟到回调由 run identifier 拦截。
- 在 CCT/HDB 收尾时新选中的设备等待当前配置完成再开始配网，并继续使用同一云同步批次。真正空闲后再选设备则开启下一批，不把整个 Add Device 页面当作永久远端缓存。
- 共享云管理器合并当前 Space 的 `syncSpace` 和同 Site 的 `syncSite` / `addSpaces` 等待请求，保留调用者回调及混合请求中的其他 Space。无关 Site、独立其他 Space、Gateway 维持原调度；恢复入口的 cleanup 和最终候选均跳过活跃添加 Space。
- 原来已在途的同 scope 同步先收尾，之后才放行配网。历史 pending 使用现有完整上传恢复流程，包括首次 Site 创建的回执及地址资源恢复；没有历史 pending 时，登记批次不发请求。等待中的既有请求并入本批最终快照；已发出的最终 POST 后产生新修改则排入下一代，保留旧提交确认语义。
- 添加内嵌 Session 的 `publishesCloudChange=false`，仅关闭其 `.device` 云通知；普通 Sync 默认仍通知。HDB 添加完成由批次直接提交一次包含当前 Space 的 Site 同步，两个页面不再重复发送地址云通知，原 UI 刷新通知保留。
- 成功、部分失败、无成功但已入网、停止及页面销毁都使用同一收尾边界。Session 自持有至停止/补偿完成，FastAdd 停止回调也持有批次，云收尾不依赖页面的弱引用。无本地变化不制造空上传；断网仍保留 dirty 供现有恢复处理；旧账户、网络身份或批次回调不更新新上下文。

没有新增业务源文件、SDK API、依赖或品牌条件分支；批次对象放在已有五品牌共享的 `HDBDeviceAddCompletion.swift` 中。没有修改 SDK、固件或服务器，也没有提交 Git。

### 验证结果及边界

| 验证 | 结果 / 能证明的范围 |
| --- | --- |
| `check_device_add_cloud_batch.py` | 通过。执行生产 AddBatch、CloudSynchronizationManager、CloudSynchronizationHandle 及上传流程；1 台 / 10 台各重复保存时，中途 0 HTTP，整批正常收尾均为前读 1＋POST 1＋回读 1，所有成功回调保留。覆盖混合 Space、独立 scope、已有 timer、空操作、停止后收尾、断网恢复、等待在途提交、HDB 尾部追加、下一版本、历史 pending、首次 Site 地址恢复、权限拒绝及账户隔离 |
| `check_hdb_integration.py --add-completion` | 通过。真实 AddCompletion 的本批节点选择、旧批迟到回调、无页面引用时的收尾持有、标准配置失败跳过、持久化失败及取消 |
| `check_hdb_integration.py --add-execution` | 通过。真实 Store / Service / 订阅、发布、初始化 ACK 持久化及完成顺序；保留摘要先保存、外部版本变化拒绝旧 ACK 等断言 |
| `check_sync_execution_session.py` | 通过。真实 Session / Coordinator 的完成、停止补偿、重试与通道所有权；新增调用方负责云通知的用例，同时验证普通 Session 仍发一次通知 |
| `check_site_zone_cleanup_batch.py .local-sdk/nordic-sig-mesh-sdk` | 通过。现有 cleanup / 三入口 / SQLite / 失败取消与重启恢复；该夹具的批次标记为边界替身，活跃批次跳过逻辑由新增云批次夹具执行 |
| `check_space_recovery_receipts.py` | 通过。真实回执、安全校验、历史兼容、未知结果、权限、版本和持久化恢复逻辑 |
| `git diff --check` | 通过 |
| SunSmart generic iOS Debug | 最终增量构建退出码 0；同次 Xcode 构建记录为 0 errors / 15 warnings，App 可执行文件更新于 2026-10-22 19:40:07 +08:00。初轮为 0 errors / 75 warnings，后续因补齐历史首次 Site 恢复边界进行了必要增量构建 |

新增云批次夹具的数据库、导出、网络及回执读接口为受控边界，实际 HTTP 发送器也为替身；它执行真实调度和 POST 流程，不是用“管理器替身收到一次调用”代替验证。它没有在同一进程内执行真实 BLE、SQLite 和完整回执服务，这些分别由现有 HDB、SQLite、回执回归覆盖。因此 **3 次是正常条件下的受控验证结果，不是新真机网络日志的实测值**。首次 Site 创建、历史提交恢复、地址申请、冲突及失败重试仍可能增加请求。

运行中批次测试二进制曾有一次 SIGSEGV 退出且没有诊断堆栈；相同代码随后单次重跑、连续 5 次执行及后续最终版本执行均通过，未能复现，未把原因归到 App 或环境中的任一方。初轮构建控制台出现过 `command failed with exit code 0`，已用同次退出码、0 errors 的 Xcode 构建记录和更新产物交叉核对；最终增量构建正常退出，没有据此清缓存或修改无关代码。

构建入口为 `SunSmartLocal.xcworkspace` / `SunSmart` / Debug / iphoneos / generic iOS / `CODE_SIGNING_ALLOWED=NO`，稳定 DerivedData 为 `SunSmart-feat-HDB-261020`。本地 SDK realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `8c5af55f5887e588e71f053ab44e2f6aa53a86a0`，沿用开始前既有 Node 配置及配置回读未提交差异，本任务未修改。没有新增 SDK 发布依赖；构建不代表远端 release 已含本机既有差异。共享逻辑无品牌分支、资源或 target 归属变更，以 SunSmart 代表验证，未重复其他四品牌构建。

### 最短人工验收

在既有 HDB Site、同一 Space、网络正常且没有旧 pending 的条件下，分别在 Classic / Professional 添加 1 台、多台，再测部分失败/停止：

1. 从 `[HDB][AddBatch] stage=begin` 到本批所有配置结束，确认没有由本批保存启动的 Space 读取或上传；开始前已有请求及必要地址申请分开计数。
2. `[HDB][AddBatch] stage=finish` 后按 `[HTTP][Request]` 统计，正常为前读、Site＋Space 上传、确认回读各一次。确认成功设备可用，失败设备保持待修复，摘要与地址资源正确。
3. 同页再次添加一批，上一批设备不重发 HDB 配置、不重新 pending；在 HDB 收尾时追加设备，应等前一轮完成后继续，本次连续任务最终只统一同步一次。停留结果页/无变化退出不额外上传。
4. 添加中断网后结束，再恢复网络，确认本地修改仍在且可恢复同步。以上为实施当时的待验收项；最新双设备成功路径已由本文顶部现场日志验证，其余场景与 UI 手感仍待验收。

## 2026-10-22 实施前代码复核与修复计划（历史记录）

### 当前结论

**以下是实施前快照：当时频繁云同步问题仍存在，尚未实现批次合并。** 当前 App HEAD 为 `69c6ed900b44cbaecddb3ba4897846e4152b8ae0`，分支 `feat/HDB-261020`；复核开始时工作树干净。相对初次分析，`CloudSynchronizationManager.swift` 和 `NetworkRequest.swift` 没有变化；HDB 的近期修复调整了模型、订阅及准备规则，但没有移除中间云同步或完成时的双重通知。

另外确认一项与连续批次直接相关的问题：两个添加页面把页面累计的 `addSuccessNodes` 传入本轮 HDB 准备，使上一批已经完成的设备再次按“刚配网完成”处理，产生不必要的配置重发和云同步。该问题应与批次边界一起修复。

原日志的 **18 次 HTTP 只是 2026-10-21 样本值**，不能表述为当前版本依然固定 18 次。本轮没有新真机 HTTP 日志；当前受控复现统计的是云同步排队次数。

### 当前证据

| 问题 | 当前源码证据 | 结论 |
| --- | --- | --- |
| 每次 HDB 保存立即同步 | `HDBConfigurationStore.update` 本地保存后仍执行 `enqueueSpaceSync(..., .promptly)`；`HDBDeviceSyncTask.persist` 的订阅/发布准备任务仍调用 Store，即使 HDB 配置字段无变化 | 仍存在；必要的本地持久化与即时云请求耦合 |
| 添加完成重复同步 | `SyncExecutionSession.finishRun` 先回调 `onSettled`，随后仍发送 `.device`；Classic/Professional 完成闭包各自发送 `.network(.address)` | 仍存在；最终产生 `.syncSpace` 与 `.syncSite(..., [space])` 两种操作 |
| 替换任务未合并实际 HTTP | 相同类型任务仍采取 cancel 后立即 start；`syncSite` 与 `syncSpace` 不相等；普通 async `NetworkRequest.request` 仍未转发 Task 取消 | 仍存在；取消不等于尚未发送，也不能收回已发出的 HTTP |
| 自动恢复缺少添加批次边界 | `resumePendingSynchronizations` 依据 dirty/pending/currentHandle 判断，前置 cleanup 和最终上传选择均不知道添加是否仍进行中 | 修复时必须覆盖，否则跳过中间上传后可能由恢复入口重新触发 |
| 连续批次重新处理旧设备 | 两个添加页面仅向 `addSuccessNodes` 追加，没有按批清空/过滤；每轮都把整个数组传给 `hdbCompletion.run`；后者对所有 eligible 节点调用 `prepareIntent(..., subscriptionsWereReset: true)` | 新确认关联问题；旧节点再次进入 `restoreDevice`，把已同步配置字段改回 pending |

复用现有 `scripts/check_hdb_integration.py --add-execution` 的生产 Store、Service、AddCompletion 与 ACK 持久化代码，仅在临时生成的夹具中增加计数。该设备夹具包含 LC 及三个 Sensor 订阅、Presence 发布、初始化六个任务：

| 受控场景 | BLE 配置开始前排队次数 | HDB 完成协调器结束时累计次数 |
| --- | ---: | ---: |
| 首次添加 1 台 | 4 | 10 |
| 同一批首次添加 10 台同类设备 | 31 | 91 |

在这个特定夹具中，准备阶段为 1 次批次摘要保存＋每台 3 次意图保存，执行结果为每台 6 次保存，合计 `1 + 9 × 设备数`。传感器/Model 结构不同，任务数会变化，不能推广为所有硬件的固定公式。

上述统计**不包含真实 Session 完成通知和两个页面收尾的额外触发，也不是 HTTP 数量**：云管理器、传输及数据库为受控边界，真实请求会受到任务替换和响应交错影响。原有执行夹具也已跑到末尾通过，确认该计数路径可以完成初始化并保持可用。

额外受控复现：将已完成、`needsSync=false` 的同一节点再次交给 AddCompletion，未重新配网，立即新增 **2 次云同步排队、3 个配置步骤，`needsSync` 变为 true**。结合当前页面确实传入累计节点数组，说明下一批会重新处理上一批设备；这不是为了修复真实重新配网所必需的操作。

本机映射 SDK 为 `.local-sdk/nordic-sig-mesh-sdk` → `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，SDK HEAD `8c5af55f5887e588e71f053ab44e2f6aa53a86a0`，有既存未提交修改，本任务未改动 SDK。夹具按脚本使用该映射 SDK 当前的 `isKeybindComplete` getter，不能将结果当成远端 release SDK 或真实 BLE 验收。

只读检查 SDK 的 FastAdd 确认：正在添加时继续收到设备会追加队列；新一轮会清空上一轮 success/fail 列表；完成时先 reset 再调用批次完成回调。因此 App 可复用当前回调承接本轮节点，不需要新增 SDK API。仍须用 App 自身的待处理设备、标准配置及 HDB 收尾状态共同判断终态，不能仅以页面存活或某个节点完成作为边界。

### 本次实施范围与选择

实施仅限 App：HDB 添加流程、共享云调度的受影响 scope、相关回归。保留现有协议、MAC/Model 元数据规则、ACK 校验、版本保护、恢复默认配置与本地持久化机制。

比较三种做法：

- **全局移除 Store 自动上传**：会改变 Lighting Zone、Lighting Configuration、Restore、独立 Sync 等全部使用方，不采用。
- **把 `.promptly` 改为固定延迟**：长批次仍会中途上传，也不解决双收尾和旧节点重配，不采用。
- **为 HDB 添加建立受限批次，在共享云调度入口合并请求**：保留现有业务保存及恢复机制，覆盖直接调度和通知入口，作为本次方案。沿用 `SpaceSyncCleanupCoordinator` 的准备流程，但它目前只合并 cleanup，无法替代上传前 `resumeUpload` 与最终提交的批次调度。

### 修复步骤

1. **先修正本批设备归属。** 两个添加页面区分“页面累计结果”与“本轮实际配网节点”。保留前者给原有回调/页面展示，HDB 准备只接收本批节点；基于 FastAdd 本轮结果及配网回调记录核对 UUID、当前节点实例和地址，不能只清空累计数组破坏原有回调语义。仅对本轮真实配网节点传递 `subscriptionsWereReset: true`。标准配置失败的已入网节点仍记录到最终云快照，但不冒充 HDB 初始化完成。
2. **建立一个共享的添加批次对象。** 由添加流程持有，两个模式复用。第一台实际开始配网前登记当前账户、区域、Site、Space、网络身份和批次 token；后续追加设备加入同批，HDB 收尾期间不释放。任务未结束时的本地节点、配置和 ACK 保存继续进行；一旦节点或地址资源持久变化，及时保留 Space/Site 的待上传标记，确保在 HDB 阶段前崩溃也可恢复。
3. **在共享云调度处暂停本批新上传，合并待同步意图。** `CloudSynchronizationManager` 在启动 timer/异步准备和发出请求前识别活跃批次。当前 Space 的 `.syncSpace` 与携带当前 Site 地址快照的 `.syncSite` 合并等待，不逐次执行 baseline、export、POST，也不每次取消重建一个已运行任务。保留 wait 状态、调用者回调及请求的 Space 集合，最终 `.syncSite(..., syncSpaces:)` 包含当前 Space；混合多个 Space 的既有请求不得丢失其他 Space。无关 Site、独立其他 Space 上传和网关操作保持原行为；同 Site 的整站请求若共享地址快照，可延后并保留完整意图。
4. **让恢复和已有任务遵守相同边界。** 前台/网络恢复的 `shouldPrepare` 和最终候选过滤都跳过活跃批次，避免先做 cleanup 改版本、再到上传入口才被拦截。开始时已排队未执行的同 scope 工作并入等待；已有在途提交不能当成未发送丢弃，也不能仅靠 cancel 宣称停止。若旧提交/回读仍可能改变配置，先让既有提交按原恢复契约收敛，再启动本批会修改配置的流程。此类历史请求另计，不强行满足 3 次目标。
5. **统一完成通知与唯一提交。** 给内嵌 HDB 执行会话明确的“云提交由调用方负责”模式，仅抑制其自动 `.device` 云通知，保留执行状态和普通 Sync 默认行为。批次在所有配网、标准配置、HDB 任务及取消清理收尾后，刷新持久化快照/摘要和 Site 地址版本，直接通过现有云管理器提交一次 `.syncSite(site, syncSpaces: [space])`；已有合并请求包含其他 Space 时保留它们。两个添加页面保留 UI 刷新通知，云提交不再依赖两个平行通知，也不能依赖已释放页面的 `weak self` 才执行。
6. **保证所有终态和版本连续性。** 成功、部分失败、全部失败但已分配地址/创建节点、取消、计划失效、页面销毁只允许终结一次；完全未改变持久数据时不制造空上传。断网保持 dirty，恢复后重试；重启不持久遗留“暂停”开关。仅延后调度，不提前创建上传 submission、不设置配置 blocked，避免阻断自己的 HDB 保存。账号/区域/网络身份变化后旧 token 不得操作新上下文；晚 ACK 不增加第二次提交。在途上传后新加入的操作进入下一版本，旧回读只能确认其提交版本。

正常路径继续复用 `resumeUpload`：**整批结束前不重复读取；最终上传前读取一次 → Site＋Space 上传一次 → 回读确认一次**。不新增入页读取，不以页面未退出作为快照永久有效的依据。当前新增的默认恢复分支也不绕过；历史待确认、旧格式恢复、远端变化及重试需要多少请求，仍由既有保护语义决定。

### 预计涉及的 App 文件

| 文件/模块 | 必要职责 |
| --- | --- |
| [DeviceAddClassicModeController.swift](../SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift)、[DeviceAddProfessionalModeController.swift](../SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift) | 本批节点、配网生命周期、取消及唯一终态接入 |
| [DeviceAddViewController.swift](../SunSmart/Main/Device/Controller/DeviceAddViewController.swift) 及一个小型共享批次对象 | 共享批次所有权、追加/切换限制、页面释放后仍可完成收尾 |
| [HDBDeviceAddCompletion.swift](../SunSmart/Main/Device/Model/HDBDeviceAddCompletion.swift)、[SyncExecutionSession.swift](../SunSmart/Main/Space/Model/SyncExecutionSession.swift) | HDB 收尾边界、调用方负责最终云提交；普通 Sync 保持默认通知 |
| [CloudSynchronizationManager.swift](../SunSmart/Common/Cloud/CloudSynchronizationManager.swift) | 按 scope 合并等待、请求启动前检查、恢复入口排除、终态提交 |
| [SpaceViewController.swift](../SunSmart/Main/Space/Controller/SpaceViewController.swift) 中 SpaceData 本地变化/调度扩展 | 本地 dirty 与 Site 地址变化持久化、最新快照提交，保留其他使用方语义 |
| 现有 HDB 添加、Sync 生命周期、云恢复夹具及新增批次行为夹具 | 验证请求次数、真实完成通知和失败/恢复行为，不以源码字符串匹配代替执行 |

`HDBConfigurationStore` 的保存与默认自动同步保留；如果实施需要抽取“标记待上传/排队”小接口，应保持非批次调用默认行为不变。模型、协议和 SDK 公共 API 不需为此修改。共享源文件覆盖五品牌；新增文件需核对五品牌 target 归属。

普通 async HTTP 取消传播是另一个已确认的通用改进点。本次优先消除请求启动源头，并补齐调度入口的取消/token 检查；**不顺带重写所有网络请求的取消语义**。如果另行实施该优化，需单独覆盖“取消前未发送、已发送但结果未知、POST 已接受”的回执保存与 continuation 单次完成，不能把取消当成服务器未执行。

### 验收与执行顺序

1. 先把当前三类行为复现固化到夹具：单台/10 台反复排队、双重完成通知、下一批包含旧节点导致重新 pending。保留现有准备、取消、持久化失败和严格 ACK 用例。
2. 修复本批归属并加入批次调度/唯一收尾；使用真实 App 协调和 Session 完成逻辑，网络边界受控，断言单 Space 正常路径只有一个提交轮次：前读 1、POST 1、后读 1。不得只断言云管理器替身被调用一次来代替 HTTP 路径验证。
3. 覆盖批次内追加、多批不退页面、空操作、部分失败、标准失败但已入网、取消/页面销毁、前后台与网络恢复、重启 dirty 恢复、旧提交未确认、账号/Space 切换、其他 Space 与混合 Site 请求、迟到回调、新版本在途变更、远端权限或成员变化。
4. 证明非添加路径不回归：普通 Site 添加、独立 Sync、HDB Zone/Lighting Configuration 编辑与 Restore 仍按原有权限和自动同步机制工作。旧设备在下一批不重新变成 pending、不新增 BLE 配置任务。
5. 必要回归包括 `check_hdb_integration.py --add-completion/--add-execution`、`check_sync_execution_session.py`；云恢复改动选用 `check_site_zone_cleanup_batch.py`、`check_space_recovery_receipts.py` 相关用例并补充实际调度行为。通过后构建一次 `SunSmartLocal.xcworkspace` 的 SunSmart generic iOS Debug；新增源文件归属带来跨品牌编译风险时稳定后覆盖受影响品牌，SDK 本机差异另列发布依赖，不将本地编译等同远端依赖就绪。
6. 人工以同一 Space 单台、多台、部分失败/停止各获取新日志；同等条件下确认中间无本批配置上传、结束一个最终提交轮次、结果页停留及无变更退出不重复请求、重进 pending 可继续修复。只有现场日志能确认最终 HTTP 数与设备行为。

本轮已执行：现有 AddCompletion 回归、AddExecution 回归（临时加入计数后跑完），以及 10 台和旧节点重复准备的受控探针；均完成。探针仅在临时目录生成 Swift，没有修改仓库测试或业务代码，已清理本轮 Python 导入产生的缓存。未执行 App 构建、真实 BLE 或云端联调。以上为实施前验证；后续实施与新验证见本文顶部。

## 2026-10-21 初次日志分析结论（历史记录）

这段日志记录了 **18 次实际 HTTP 请求：13 次 Space 读取、4 次 Space 上传、1 次 Site 上传**。13 次读取中，8 次为上传前基线读取，5 次为上传后的回读确认。不是 18 次独立、必需的添加设备业务操作，也不是 HTTP 失败重试造成的数量膨胀。

建议采用“整批添加任务结束后统一同步”：过程中及时保存本地节点、配置意图和成功/失败结果；所有添加及 HDB 配置任务成功、失败或取消收尾后，仅提交一次包含受影响 Space 的 Site 同步。

在与本样本相同的既有 Site、单 Space、无历史待确认提交、无冲突和重试条件下，目标为 **3 次 HTTP：上传前读取 1 次 → Site＋Space 上传 1 次 → 上传后回读 1 次**，比样本少 15 次，约 83%。这是根据现有接口及保护流程推导的目标，尚未实现或实测。

不能把“统一同步一次”理解为必须只有一次 HTTP：上传前校验和上传后确认分别保护不同的一致性边界。

## 证据范围与计数口径

- 输入日志：[add device log.txt](</Users/maginawin/Desktop/doing/xyy/add device log.txt>)，共 1541 行。
- 工作树：`feat-HDB-261020`；分支：`feat/HDB-261020`；HEAD：`215fe00662d52d7c41d2693e20c999d82914d16b`。
- 任务开始时生产源码无未提交改动，已有三份 HDB 设计/分析文档的未提交修改。交付检查时观察到其他工作正在修改 `HDBConfiguration.swift` 及相关测试；本任务未修改这些文件。本分析对应本轮读取时的添加、Store 和云同步实现，后续实施前须核对并发工作产生的差异。
- 按 `[HTTP][Request]` 计数，并用响应及非零 HTTP Metrics 交叉核对。底层 task 267～284 共 18 个，18 个响应的 HTTP status 均为 200。
- `[CloudSync][Request]` 是业务流程日志，不等于已发送 HTTP。特别是日志 1472 行又打印了一条 `syncSpace`，但后面没有对应的 Space 上传 HTTP，不能再加一次。
- 同一 HTTP task 的 Metrics 先打印零值、再打印有效值，不能按 Metrics 行数重复计数。
- 日志起点已是 Composition Data 读取，未覆盖点击添加前的全部过程；因此 18 是**这份日志可确认的实际数量**，不是所有设备或所有条件下固定的端到端数量。
- 源码未包含于日志中，具体调用来源由当前源码与阶段顺序对应；日志未携带调用点标识，不能把每个并发请求的具体调用栈视为已运行追踪确认。

## 实际请求清单

所有接口均使用 POST；路径中的 `get` 表示读取业务，不是 HTTP GET 方法。下表省略公共 `/srv2` 前缀。

| 业务 | 接口 | 实际次数 | 判断 |
| --- | --- | ---: | --- |
| 上传前获取远端基线 | `/sitespace/get/spaceprops` | 8 | 最终提交前保留一次；中间反复启动同步导致重复读取 |
| 上传中间 Space 快照 | `/sitespace/sync/spaceprops` | 4 | 可合并进最后一次 Site＋Space 上传 |
| 上传后确认 | `/sitespace/get/spaceprops` | 5 | 随上传批次合并，最终提交保留一次正常回读 |
| 上传 Site 与当前 Space | `/sitespace/sync/siteprops` | 1 | 添加改变设备地址资源，应保留这一最终同步层级 |
| **合计** | | **18** | 正常路径目标为 3 次 |

按日志顺序展开：

| 序号 | 请求所在日志行 | 请求及当时阶段 |
| --- | --- | --- |
| 1～4 | 610、622、634、646 | HDB 开始后连续 4 次基线读取；返回的解压响应均为 57099 字节 |
| 5～6 | 726、750 | 第 1 次 Space 上传及回读；订阅任务尚未完成落盘 |
| 7 | 856 | 订阅成功落盘后的基线读取 |
| 8～9 | 933、958 | 第 2 次 Space 上传及回读，与第 1 个 Publication 的结果落盘交错 |
| 10～11 | 1035、1060 | 第 3 次 Space 上传及回读，与第 2 个 Publication 的结果落盘交错 |
| 12～13 | 1138、1162 | 第 4 次 Space 上传及回读，12 条初始化命令仍在执行 |
| 14～16 | 1378、1404、1416 | 初始化落盘、添加完成前后又有 3 次基线读取 |
| 17～18 | 1477、1501 | 最后一次 Site＋Space 上传及回读 |

关键阶段：606 行 `summary-saved`，607 行 `start`；850 行订阅落盘，955/1057 行两次 Publication 落盘；1375 行初始化 `handles=12 ack=12`；1388 行 `settled-success`；1400 行 `finished`；1523 行最终回读 `confirmed`。

读取开销：13 次 Space 响应累计传输体积 113634 字节，解压后 800058 字节。日志还记录 16 次 Space 导出，`totalSeconds` 合计约 0.260 秒，均标记 `main=true`。这些数字表明存在重复传输和导出，**不能直接当作添加总耗时或优化后的提速幅度**；日志没有完整请求起止时间。

## 请求为何被放大

### 1. HDB 本地保存与立即云上传绑定

[HDBConfigurationStore.swift](../SunSmart/Common/Data/HDBConfigurationStore.swift) 的 `update` 每次都会：校验权限和配置 → 更新递增版本 → 本地保存 → `enqueueSpaceSync(..., level: .promptly)`。`promptly` 的等待时间为 0。

一个首次加入、具备传感器的设备，当前路径在 HDB 执行前就会产生四次这样的更新：

1. `HDBDeviceAddCompletion.run` 刷新设备等摘要计数。
2. `HDBDeviceSyncService.prepareIntent` 添加设备的 HDB 记录。
3. `ensureSensorGroup` 创建/关联传感器 Group。
4. `restoreDevice` 建立当前配网身份对应的初始化意图，将字段标为 pending。

这与日志开头连续四次基线读取相吻合。它们需要本地持久化，但后续 BLE 任务不需要等待这四轮云同步。

随后 [HDBDeviceSyncService.swift](../SunSmart/Main/Space/HDB/Model/HDBDeviceSyncService.swift) 中 `HDBDeviceSyncTask.persist` 在订阅、两次 Publication、初始化四个任务结束时，再分别调用一次 `HDBConfigurationStore.update`。即使 `.preparation` 不修改 HDB JSON 字段，仍会更新版本并排队云同步；节点上的订阅/发布结果确实需要保存和最终导出，但不必此时单独上传。

### 2. 同步任务替换不能等同于 HTTP 合并

[CloudSynchronizationManager.swift](../SunSmart/Common/Cloud/CloudSynchronizationManager.swift) 的 `addSynchronizationHandle` 遇到相同操作时，取消旧 handle，创建并立即启动新 handle。

上传工作首先进入 `SpaceConfigurationSafety.resumeUpload`，因此“还没有真正上传”也可能已经发出了基线读取。`syncSite` 与 `syncSpace` 属于不同 operation type，也不会由现有相等判断自然合并。

[NetworkRequest.swift](../SunSmart/Common/Network/NetworkRequest.swift) 的普通 async `request` 使用 `withCheckedContinuation`，未把外层 Task 取消传给底层 Cancellable。故取消/替换云任务不保证取消已经发出的 HTTP；`resumeUpload` 的无 submission 路径也在网络返回后才检查取消。当前代码解释了为什么短时间排队多个同步仍会留下多次完整 HTTP。不能只调整调用间隔或继续依赖“后来一次覆盖前一次”。

本次优先在请求启动前合并添加批次；通用网络 async 取消传播可以单独优化，不需要为本需求先重做全部网络层。

### 3. 最终完成有两个云同步发起者

[SyncExecutionSession.swift](../SunSmart/Main/Space/Model/SyncExecutionSession.swift) 的 `finishRun`：先调用 `onSettled`，之后仍然发送 `SpaceChangeDataType.device` 通知。

HDB 的 `onSettled` 进入 [HDBDeviceAddCompletion.swift](../SunSmart/Main/Device/Model/HDBDeviceAddCompletion.swift) 的 `finish`，再调用添加页面的完成闭包。Classic 和 Professional 两个页面都会保存数量并发送 `SpaceChangeDataType.network(type: .address)` 通知。

[SpaceViewController.swift](../SunSmart/Main/Space/Controller/SpaceViewController.swift) 的共享通知处理把它们分别变成：

- `.device` → `.syncSpace`。
- `.network(.address)` → 标记 Site 地址变化，然后 `.syncSite(site, syncSpaces: [space])`。

因此初始化最后一次 Store 保存、添加页面的地址通知、执行器自己的完成通知共同解释了结束附近的三次基线读取。仅移除 Store 中途上传仍不足以消除收尾重复。

## 哪些需要保留

| 操作 | 目的与处理建议 |
| --- | --- |
| 节点、Group、配置意图、ACK 及 pending 状态落盘 | 继续及时执行。取消、断电、重启和失败重试依赖这些记录；不能和云上传一起延迟到最后 |
| 上传前远端基线读取 | 最终同步时保留。当前逻辑检查远端权限、成员和配置变化，防止离线编辑把远端已删除设备重新上传 |
| 最终 Site＋Space 上传 | 保留一次。Site 导出包含 Provisioner 已用地址、分配范围和废弃地址；只上传 Space 会遗漏现有添加流程的 Site 层语义 |
| 上传后回读 | 保留最终一次正常确认。当前逻辑核对网络身份、实际配置及提交状态，HTTP 200 本身不足以清除待上传状态 |
| 标准配网和 HDB Mesh 指令 | 维持当前顺序及 ACK 校验。本样本 HDB 专属任务为 1 条订阅、2 条发布、12 条初始化，共 15 个 handle；不属于上述 18 次 HTTP |
| 地址不足时申请地址 | 仍需在使用新地址前执行。两个添加页面的 `applyDeviceAddressesRequest` 都依赖服务器分配后才继续添加；本日志没有这类 HTTP |

因此，这份样本中可以合并的是 **4 次中间上传、随之发生的 4 次中间回读，以及 7 次重复基线读取**，并不是删除全部读取或取消必要配置任务。

## 建议的最小完整调整

本节是待实施方案，不代表已修改代码。

1. 为当前 HDB 添加批次建立明确的云同步延后边界，覆盖所有待添加设备、标准配置和 HDB 追加任务。按账户、区域、Site、Space 识别所属批次，不能使用全 App 的停止同步开关。
2. 保持现有 Store 保存、版本递增、权限校验、任务 ACK、pending 和恢复记录。该批次产生的同步请求先合并为“需要最终同步”，暂不启动基线读取、导出或上传。
3. HDB 内嵌 `SyncExecutionSession` 将最终云同步交给添加批次统一负责。独立 Sync 页面继续保留原有完成通知；两个添加页面的 `.address` 收尾应归并到同一最终提交，不能再产生平行 `.syncSpace`。
4. 整批完成时从持久层取得最新 Site、Space 和节点快照，刷新摘要计数与地址资源，只提交一次 `.syncSite(site, syncSpaces: [space])`，复用现有安全校验、导出、提交及回读逻辑。
5. 统一收尾必须覆盖全部成功、部分成功、全部失败、取消、计划失效和页面销毁。只要节点、配网身份或地址资源已经变化，即使后续配置失败也需要同步真实结果；完全没有持久变化时无需制造空上传。使用一次性完成保护，晚回调不能再提交一次。
6. 同一 Space 的前台/网络恢复入口也应尊重活跃添加批次，避免 `resumePendingSynchronizations` 绕过延后边界。已有历史待确认提交继续按现有恢复契约处理，不能清除或伪装成功。批次结束断网时保留 dirty 版本，由已有恢复机制重试；App 重启后不会留下永久暂停状态。
7. 批次开始前已发出的请求无法追溯消除；实现时需要明确这些请求的归属，保留旧提交回执，防止迟到结果确认新版本。不要为了延后同步提前创建普通上传 submission 或设置配置 blocked 状态，以免自己的 HDB 保存/校验被阻断。

这里复用现有本地版本、pending、云队列及安全恢复机制，只增加添加期间的合并边界，不另建第二套上传系统。单纯把 `.promptly` 改为 5 秒/10 秒仍可能在长批次中途触发，也无法解决双收尾，不建议作为最终方案。

## 关联影响和边界

- `HDBConfigurationStore.update` 也被 Lighting Zone 编辑、成员调整与重试、Lighting Configuration 意图/字段回执、设备恢复和普通 Sync 使用。不能全局移除自动同步，否则这些入口会失去持久化后的云同步触发；延后策略仅对活跃添加批次生效。
- Classic 与 Professional 共用相同问题链路，两个入口都要覆盖。Professional 支持追加候选设备，批次结束应以当前队列及 HDB 任务实际结束为准，不能用固定时间或第一个设备完成作为边界。
- 共享 App 代码涉及五个品牌编译，实际业务作用范围由 HDB Site 及入口可见性决定。方案不要求新增 SDK API、不改协议、不改正式依赖，也不需要固件或后端变更。
- 批次中途云端暂时看不到新设备的最新配置；本地结果持续保存，正常结束后一次更新云端。这是采用批次同步的预期行为。
- 本日志全部 HDB 任务成功，不含失败、断网、重启或多设备样本。对这些路径的处理要求来自代码依赖分析，不能写成已现场验证。

## 实施后的验证要求

1. 在受控云请求边界验证：中间 Store 保存不发 HTTP；单设备及多设备正常完成只启动一次最终同步；原独立 Sync 和 HDB 编辑入口仍能自动同步。
2. 覆盖部分成功/失败、全部失败但地址或节点已变化、取消、晚回调、页面销毁、前台恢复与网络恢复；一次性收尾不得遗漏或重复。
3. 继续覆盖本地持久化失败、重启后 pending 恢复、外部版本变化导致 ACK 失效、旧提交回读与新版本隔离、远端权限变更及成员删除保护。
4. 优先扩展 `HDBDeviceAddCompletionTests`、`HDBDeviceAddExecutionTests` 和现有云提交确认用例。现有 HDB fixture 的云管理器是快照替身，不能用这些用例单独证明真实 HTTP 次数或完整 Session 通知行为；需补充覆盖真实收尾和同步调度的受控边界。
5. 实施完成后执行相关回归，并进行一次受影响代表 scheme 的 generic iOS Debug 构建。若引入 target/资源/公共 API 风险，再扩大品牌构建范围。
6. 人工验收最短路径：相同 HDB Space 添加一台同类设备，确认 HDB 配置完成且无遗失状态；日志中正常路径出现一次最终上传及一次前读、一次后读；再测批量部分失败/停止，重进仍能看到准确 pending 状态并重试。

## 补充：多设备批量添加与页面级远端读取复用

2026-10-21 根据后续问题补充；仍为分析，未实施。

### 多设备也应按批次计数

`HDBDeviceAddCompletion.run` 接收 `[Node]`，准备各节点意图后创建一个 `.devices(eligible)` 执行会话，再通过统一完成回调交还添加页面。因此云同步合并应覆盖这组设备及其所有追加配置任务，而不是每个设备各启动一次同步。

在同一既有 Site、同一 Space，无历史恢复、地址申请、冲突和重试的前提下，预期配置同步请求数如下：

| 操作 | 优化后的目标 |
| --- | --- |
| 同批添加 1 台 | 一次前读＋一次合并上传＋一次后读，共 3 次 |
| 同批添加 10 台 | 同样共 3 次，上传体积及 BLE 工作量随设备数增加 |
| 同批 10 台，其中部分配置失败 | 有持久变化时同样一次最终同步，携带成功结果及未完成状态 |
| 本批完成并已同步，页面内再开始下一批 | 下一批再执行一次同步流程；两个正常批次目标共 6 次 |
| 已同步完成后退出页面，没有新变化 | 不新增配置同步请求 |

不能用本次单设备的 18 次直接推算当前 10 台必然有 180 次；现有任务替换、请求交错与耗时都会影响实际数量。上述 3 次/批次是待实现目标，不是当前实测结果。

### “页面一直打开”不能作为远端快照一直有效的依据

当前 `DeviceAddViewController.viewDidLoad` 主要初始化 UI，本身没有建立云端独占编辑会话。添加页面存活期间，其他手机仍可能修改同一 Space 的配置、删除设备或调整当前账户权限。

具体例子：进入页面时读到设备 A、B；另一台手机随后删除 B；本机添加 C 后若跳过上传前读取，仍可能提交包含 B 的旧本地快照，削弱现有防止远端删除被旧数据覆盖的保护。上传后的回读即便与自己刚写入的内容一致，也不能证明没有覆盖别人此前的修改。

当前 `SpaceConfigurationSafety.resumeUpload` 的基线读取不仅用于页面展示，还会应用远端权限元数据，并调用 `reconcileCloudProfiles` 和 `reconcileCloudMembership`。这些判断依赖读到的远端内容，不能仅用“账户没换、页面没退出、本地没变”证明远端仍然一致。

已核对 App 的 `siteUpload`/`spaceUpload` 请求参数与请求头：可见本地 `updateTimestamp` 和完整配置上传，但未见明确提交“我基于哪一个远端版本修改”的独立字段或 `If-Match` 条件。不能据此断言服务器没有并发保护，也不能假定已有足够的服务器契约允许 App 无条件复用整个页面生命周期的旧快照；本轮未核对后端实现，不需要为这次 App 优化修改后端。

### 推荐的读取时机与复用范围

1. 不为减少请求额外增加一次“打开 Add Device 页面即读取”；已有入口权限或历史恢复检查如确有需要，仍按原语义保留，不计作可任意删除的重复同步。
2. 批次中仅做必要 BLE 工作和本地落盘；所有设备共用一次最终云同步，不按设备读取、不按 ACK 读取，也不因页面停留而定时读取。
3. 全部排队、配网、标准配置、HDB 配置及取消清理完成后，在最终上传前读取一次。其结果供本轮校验、协调及导出流程使用；同一轮内的重复发起者应合并，而非重新读取。
4. 上传一次，再回读一次确认该提交。现有 `finishSubmission` 已把确认后的配置、节点身份等保存为下一次比较基线，避免仍拿入页旧快照判断后续新增设备。
5. 下一批即使在同一页面内，也按新的提交轮次处理；上一轮确认快照可作为比较基线，但不能冒充新一轮的实时远端读取。断网恢复、后台返回、账户/区域/Space/网络身份变化、权限或冲突异常、未确认历史提交，也不能沿用“页面未退出所以有效”的判断。

读取尽量靠近上传，可缩短快照变旧的窗口，但并不能宣称消除了读取与写入之间的一切远端并发。若未来要求长时间完全不读取仍保证并发一致性，需要先确认服务端有原子的版本条件写入或等价契约；不将该外部能力作为本次方案前提。

### 批次结束与页面退出分开判断

- 仍有排队设备、正在添加设备、HDB 配置或取消清理时，不提交最终同步；过程中追加的设备可纳入尚未收尾的批次。
- 全部任务终止后即可同步，不必等用户退出页面，避免用户留在结果页时云端长期缺少已添加设备。
- 最终上传快照已开始生成或提交后，新增操作属于后续版本，不能修改在途快照或用旧回读确认新版本；必要时下一批再同步。
- 添加页面的 `addSuccessNodes` 会累积成功节点，不能仅靠此数组判断“当前批次仍有任务”；需结合真实排队、执行和 HDB 收尾状态。
- 延后同步仍需覆盖 Classic、Professional 和前台/网络恢复旁路；保留本地 pending、版本和失败恢复，不改变其他 Space 的正常同步。

补充验证应覆盖：同批 10 台只产生一次云提交、运行中追加设备、连续两批不退出页面、部分失败与停止、在途上传后新增设备，以及另一端在页面停留期间修改/删除设备时最终读取仍能发现变化。当前没有多设备现场日志，以上为代码支持的方案与待验证边界。

2026-10-21 初次分析仅完成日志计数、源码链路核对及方案记录，未运行回归、未构建、未操作真机、未请求实际服务器。2026-10-22 的当前代码复核及受控验证见文首。
