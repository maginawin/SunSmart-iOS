# 同 Site 跨 Space 重复设备归属修复

## 问题与处理结果

用户场景：设备在 Space A 配网后被强制重置，再添加到同一 Site 的 Space B。Site 页面数量可能已反映云端去重，但 App 的两个 Space 仍各自保留设备及其引用。

根本原因是节点按 Space 子网持久化，Site 的数量字段不是旧 Space 节点及引用的清理指令。原永久删除流程又要求当前活动子网匹配，不能直接用于后台清理其他 Space。

本轮基于 `b72afaee` 增加 App 侧归属协调：以同 Site 内规范化 MAC 识别同一物理设备，保留最新入网实例，清理其他 Space 的旧实例。云端按 MAC 去重是用户提供的系统行为预期；本轮没有读取或修改服务端实现，也未调用生产接口验证该规则。

## 归属判定

- Site ID 是硬边界；不同 Site 中相同 MAC、UUID 或地址不会构成跨 Site 删除依据。
- MAC 统一大小写并接受冒号、短横线分隔；空值、格式错误、全 0、全 F 不作为物理设备身份。
- UUID 和地址用于精确识别被移除的入网实例，不作为物理身份的唯一依据，也不按地址大小判断先后。
- 历史记录使用有效 createdTimestamp 判定最新实例；同秒且没有明确添加证据、缺少必要世代信息时保留数据，不猜测归属。
- 本机明确配网完成时，以这次添加作为最新归属证据。若创建时间不大于其他 Space 旧实例，持久化为旧世代最大值加 1，处理同秒添加和手机时钟回拨；整数溢出则不继续删除。
- 写入失败后的重试，从已有删除日志恢复这次明确归属决定，并重新核对保留实例仍存在，没有更晚实例取代它。
- 删除前验证新实例已落盘，检查旧节点全部元素地址与其他节点不重叠；权限不足、待导入、损坏数据等情况继续保留原保护约束。

这套历史排序依赖现有入网时间数据。跨手机时钟不一致且没有可用本地添加证据的异常历史记录，不能仅靠 App 快照保证物理操作的真实先后；若服务端提供权威归属版本，应以其协议进一步收敛。

## 执行入口

- Classic / Professional 添加设备的配网完成回调。
- Restore 完成时的设备保存回调；只处理其他 Space 的重复实例，同 Space 的 Restore 引用迁移继续使用原流程。
- Site 云数据导入完成后，在主线程处理所有已持久化 Space。
- Site 页面出现时检查已有本地数据，离线也可清理历史重复项，并刷新 Space 列表数据源。
- 网络恢复及前台自动同步发现待上传任务时，再次检查和恢复未完成清理。

成功清理使旧 Space 变为待上传；在线时接入现有同步队列，离线时保留回执供之后恢复。过程不切换当前 Mesh 子网，不向重新配网的物理设备发送 Reset。

## 旧实例的清理范围

| 范围 | 行为 |
| --- | --- |
| Node / Group 成员 | 删除旧 Space 的节点记录及其节点属性、订阅归属；Group 和其他设备保留 |
| Scene | 移除旧节点的全部元素地址，并保存、回读确认 |
| Scheduler | 从 nodeAddresses 和 needDeleteNodeAddresses 移除主地址及其他元素地址，并回读确认 |
| Group Path / Sequence | 复用完整拓扑事务，清空该设备对应的路径位置，保留路径结构 |
| Group Trigger Zone | 移除该设备地址，保留其他成员 |
| Space Trigger Zone | 移除该设备成员，保留其他成员 |
| 其他既有扩展引用 | 沿用传感器绑定、Switch Proxy、固件分发缓存等永久删除清理 |
| Site Gateway 记录 | 迁移删除不按 MAC 删除 Site 级记录，防止误伤新归属 |
| UI 计数和缓存 | 持久化旧 Space 的 deviceCount / luminairesCount，刷新 Site 数据源和已有设备删除通知、拓扑同步缓存 |

引用和拓扑变化发生在旧 Space。剩余设备的实际 Mesh 参数仍通过已有同步任务机制收敛；后台清理不会借用新 Space 的连接向旧 Space 设备发送命令。

## 持久化与上传确认

- 复用 SpaceDeletionJournal，增加可选 replacement 证据；旧日志可以继续解码。
- 先记录旧实例与新归属证据，再删除节点；节点、Scene、Scheduler 和拓扑回读通过后，将回执标为 cleaned。
- 删除失败或清理中断保留日志，下次进入 Site / 恢复任务时重试。原有普通删除回执流程继续可用。
- 对早于这次迁移的待确认提交，允许仅从其期望设备成员中排除已确认被迁移的旧 UUID+地址，以适配云端已移除旧归属的结果。
- 新的清理回执不由旧上传版本确认，仍需再次上传完整清理结果。
- 授权恢复比较和完成后的授权基线采用同样的、受迁移证据限定的规则。
- 其他设备、Group/Profile、Path、Trigger Zone 差异仍严格比较；不会因为一个设备迁移而无条件结束其他配置冲突。如果远端还有其他差异，保留原冲突诊断与保护。

## 验证记录

- `bash scripts/check_path_topology_persistence.sh`：通过完整拓扑、生命周期、导入、回读和持久恢复回归。
- 新增生产归属协调器执行测试：同 Site 同 MAC 保留最新实例；跨 Site 隔离；MAC 格式；同秒明确添加；删除写入失败后持久证据重试；重复执行幂等；活动网络不切换。
- 新增清理断言：Scene 主/附加元素、Scheduler 活跃/待删除地址、Sequence 位置、Group Zone、Space Zone 全部移除目标，其他设备和容器保留。
- 新增显式配网回调测试：模拟时钟回拨，确认新实例获得更晚世代，并仍保留在最后添加的 Space。
- 新增生产上传恢复测试：云端去掉已迁移旧实例时可确认较早提交；较新清理回执保留；其他设备意外缺失仍被拒绝；权限恢复同样接受有效迁移证据。
- 新源文件已加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 五个 target。
- SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 五品牌最终 generic iPhoneOS Debug 无签名构建全部通过，退出码均为 0；既有资源、重复构建文件及其他编译警告未作为本轮范围处理。
- `git diff --check` 通过。没有修改 SDK、资源或本地化，没有 Git commit / push。

测试使用生产策略、归属协调器、删除流程与恢复方法，替换 SDK 存储、网络及 UI 边界。实际设备强制重置、跨 Space 添加、服务器去重和其他手机读取的验收尚未执行。

## 真机验收路径

1. 在 A 中添加灯并加入 Group、Scene、Scheduler、Path/Sequence、Group Trigger Zone、Space Trigger Zone；保留一台其他灯作对照。
2. 强制重置目标灯，添加到同 Site 的 B。确认 B 保留新实例，A 列表不再显示目标灯。
3. 检查 A 所有上述配置：仅移除目标设备引用，其他灯、Group、Scene、Scheduler 及路径容器保留。
4. 查看 `[SiteDeviceOwnership] ... result=cleaned`，随后确认 A 的云端清理上传完成；再次进入 A/B，并用另一手机读取验证。
5. 离线重复同流程，恢复网络；补测已有旧上传待确认记录、同秒添加、删除写入中断后重启。
6. 不同 Site 的同 MAC 记录保持不变。出现真实远端配置差异时，继续收集 SpaceConfigurationReadback / SpaceConfigurationDiff，不清空恢复标记。
