# 同步失败时删除设备：实施与验证

日期：2026-09-10。工作区：site-trigger-zone。基于 HEAD 5773a918，按用户确认的调整方案实施；未提交 Git，未操作手机或生产云端记录。

## 交付行为

- 普通删除与云端同步结果解耦。正确的活动 Mesh 网络、持久化设备实例和密钥可用时，沿用 Reset；网络或 Key 条件不满足时，直接显示现有 Force Delete 确认。
- Force Delete 移除所选本地设备记录，实体设备需手动恢复出厂。它不伪造 Reset 成功或云端同步成功。
- Lights 全选/部分选、单灯、通用 DeviceProtocol 和 Dongle 统一使用共享删除流程。空选择不启动删除；代理设备保留最后 Reset 的顺序。
- 回调根据持久化结果区分未删除、已移除但清理待重试、清理完成。只从列表移除已证实删除的设备；失败项保留。剩余设备的邻近照明配置留待后续同步，不再阻塞已经完成的设备删除。
- 非空 Space 的删除放行已撤回。Site 和 Space 两个入口及共享删除请求入口，均要求设备记录清空；检查实际 Mesh 节点、Switch、Dongle、Emergency/Fire 记录，以及本地清理/导入状态。缓存 deviceCount 不能代替这些检查。
- 空 Space 走原有独立删除接口，不以完整配置上传成功为前提；服务器成功或确认记录不存在后才完成本地删除。缺 Key 时按 Site UUID + Network ID 清理本地记录的已有收尾逻辑保留。

## 实施要点

1. `DevicePermanentDeletionContext` 将本地准备与 `canReset` 分开。保留账号/权限、恢复 generation、Site/Network ID、检查点与删除日志校验；本地删除不再要求当前活动 Mesh 对象等于目标对象。
2. 日志新增 `forceRequested`，记录节点 UUID、主地址、元素地址和可选 createdTimestamp。确认强删后先落盘，再删除；进程中断后即使节点仍在，也可重放。旧 prepared 条目仍按普通 Reset 的取消语义处理，旧日志可解码。
3. SDK 原删除接口内部以 Site + 地址删除。App 在无 await 的同步片段内，从目标 Space 和完整 Site 重新读取实例，核对 UUID、Network ID、地址、createdTimestamp 及同址冲突，再调用原 SDK 删除，并回读确认。未修改 SDK、依赖、Key index 或密钥值，也未实现跨 App/Mesh 两库的原子事务；中断恢复依靠持久日志。
4. 删除清理直接使用目标持久化网络。拓扑协调器只允许“原始快照减去已确认删除地址”这一差异，保存原始局部结果，不连带应用全局 normalize。既有的其他悬空引用保留并独立标记；普通编辑和云端导入仍采用原严格校验。
5. 保留 Scene、Schedule、Group/Space Zone、Path、传感器、Kinetic Switch、分发引用清理；补充 Dongle 绑定清理和目标缓存刷新。同一 Site 中仍有其他实例使用同一实体设备 MAC 时，保留共享网关关联。
6. 对 pending-import 先备份并归档其原始字节，再推进恢复 generation，使旧异步上下文失效。标记仍需远端完整基线，不能把部分导入当成完整上传数据。设备删除凭据保留至对应云端确认，旧上传回读不能清除较新的删除记录。
7. 兼容上一版 active + discardRequested：仅 GET 核验远端存在性与权限，不自动重发非空 Space 删除；远端仍存在时撤销旧意图并使旧回调失效，已不存在时交给既有 removing 收尾。网络/权限无法确认时保留状态。
8. 删除上一版“连同设备删除 Space”的英中文案；Force Delete 继续复用已有英文/简体中文文案和 SRAlertView。没有新增布局约束。

## 自动化验证

以下检查已通过：

| 检查 | 覆盖 |
| --- | --- |
| `bash scripts/check_path_topology_persistence.sh` | 拓扑策略、生命周期、导入/导出约束、恢复回执、共享删除执行及 UI 流程 |
| `python3 scripts/check_proximity_scoped_import.py` | 缺 Key 强删、活动网络不匹配、部分删除、取消、强删中断重放、重复操作、同址新实例、无关旧引用、其他 Site/Space 与网关关联保留 |
| `python3 scripts/check_space_recovery_receipts.py` | 上传失败与删除独立、旧回读保护、pending-import 归档/失效、旧 discard 意图核验、非空请求拒绝与空 Space 请求收尾 |
| `python3 scripts/check_space_record_removal.py` | 各分类非空拦截、清理未完成拦截、缺 Key 空 Space 收尾、其他 Space/密钥保留、失败重试 |
| `python3 scripts/check_space_mesh_keys.py` | Key 完整性、冲突保护、缺 AppKey 恢复、sync Site 聚合拒绝不完整数据 |
| `zsh scripts/check_device_permanent_deletion_cleanup.sh` | 直接设备 Schedule 地址清理 |
| `git diff --check` | 空白错误检查 |

新增共享 UI 执行测试编译生产 deleteNodes 方法与实际删除上下文，替身仅覆盖 BLE、界面和存储边界，验证确认、取消和逐设备回调。它不等于真实 UIKit 布局或真机交互测试。旧“必须打开邻居同步页”的静态断言已由执行测试替代；旧导入预检变量名断言改为检查当前异步 prepare 调用顺序。

五品牌均使用直接 xcodebuild、Debug、generic iPhoneOS、CODE_SIGNING_ALLOWED=NO 验证：SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux。五个 scheme 均构建成功（exit code 0）；已有资源符号、重复资源/源文件警告没有纳入本次修复。

## 验收边界与使用顺序

代码和自动化结果没有改变用户手机或云端。未安装新包，未发送实际 Mesh Reset，未执行生产删除 API，未运行 Simulator 或真机布局测试。

现场使用新构建后：进入 Lights → 选择待删除设备 → Delete → 若提示则确认 Force Delete；删除其他仍存在的设备分类，待本地清理完成后再 Delete Space。Force Delete 后实体设备手动复位。

仍需现场确认独立 Space 删除接口是否允许删除“本地已空、云端仍有旧设备”的记录。如果服务端以云端非空为由拒绝，本次不能冒充云端删除成功；需依据真实接口契约补充云端逐设备删除能力。没有新增未经确认的 API、force 参数或绕过非空检查。

未修改独立的 `260910_1450_stale_mesh_key_snapshot_fix_plan.md`；本次没有迁移现存项目的 Key 索引。
