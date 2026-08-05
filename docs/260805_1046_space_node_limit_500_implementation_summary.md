# Space Mesh Node 500 上限实施总结

## 实施结论

方案 B 已在 App 侧完成：单个 Space 的真实 Mesh Node 上限由 300 提升为 500，并将 Classic Add、Professional Add、Group 指定添加所复用的 Device Add 流程以及 Space Restore 收敛到同一容量策略。Switch 总上限仍保持 16，NordicSigMeshSDK 未修改。

## 已完成更新

- 新增统一的 `SpaceNodeCapacityPolicy`，集中定义 500 Node 上限、剩余名额、接受数量和稳定前缀裁剪。
- `SpaceData.maxDevicesCount` 改为代理统一策略，不新增数据库字段，不改变 Import/Export schema。
- `.wait`、`.addConnecting`、`.adding` 统一视为在途 Node；成功、失败和同步失败状态不重复占用容量。
- Main 的 Lights、Sensors、Others 均以 Space 全部真实 Node 数作为左下角分子；Switches 继续显示全部 Switch 数量 `/16`。
- Classic Add 的全选、逐项选择、单设备添加和最终批量添加均应用 500 Node 边界。
- Professional Candidate 提供早期选择限制，Professional Controller 在 Provisioning 前再次执行最终批次裁剪。
- Space Restore 的全选、逐项选择、批量 Restore 和最终 Provisioning 边界均应用 500 Node 限制。
- Restore 的 `space == nil` Site Gateway 路径明确绕过 Space Node 上限。
- Classic 和 Restore 的在途数量使用全部内部设备集合统计，不受当前设备类型或 RSSI 可见筛选影响。
- 只有接受后的批次会进入 Power Switch 16 校验、Group 批次准备、Element 地址计算、地址申请和 Provisioning。
- 超过剩余容量的批量请求稳定保留原顺序前 N 个，其余取消选择并沿用现有中英文容量提示。
- 新公共策略已加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 target。

## Switch 语义

- Kinetic Switch 不创建新的 Mesh Node，不占用新的 Unicast Node Address；在 500 Node 时，只要全部 Switch 少于 16 且 Group Address 条件满足，仍可添加 Kinetic Switch。
- Battery Power Switch 和 AC Power Switch 是实际 Provisioned Mesh Node；当前每台占 1 个 Node 名额、1 个 Switch 名额和 8 个连续 Element 地址。
- Kinetic、Battery、AC 三类 Switch 合计上限仍为 16，本次没有修改任何 `/16` 规则。

## SDK 与地址池

- 本地 NordicSigMeshSDK 没有 300 Node 业务限制，也没有本任务产生的代码改动。
- Node 数量限制和 Unicast Element 地址容量仍是两个独立边界。App 先检查 500 Node，再按设备 Element 数检查或申请地址。
- 是否需要 SDK 优化不能由 App 编译结果判断；只有真实 500 Node 压力测试证明 SDK 存在性能或正确性瓶颈时，才应另立 SDK 任务。
- 服务端 `applyAddress` 是否能持续提供满足 500 Node 与多 Element 设备的地址范围，仍需真实服务器环境验证。

## 自动验证结果

- `SpaceNodeCapacityPolicyTests`：通过。
- `SpaceNodeCapacityIntegrationContractTests`：通过。
- `scripts/check_space_node_capacity.sh`：通过，包含四 target membership 检查。
- `git diff --check`：通过。
- SunSmart generic iPhoneOS Debug：`BUILD SUCCEEDED`。
- Archipelago generic iPhoneOS Debug：`BUILD SUCCEEDED`。
- SLG Sync Plus generic iPhoneOS Debug：`BUILD SUCCEEDED`。
- SylSmart generic iPhoneOS Debug：`BUILD SUCCEEDED`。
- NordicSigMeshSDK Git 状态：本任务未产生修改。

构建期间观察到的 Archipelago/SylSmart Info.plist Copy Bundle Resources、SLG Sync Plus/SylSmart FSCalendar 重复源文件以及 AppIntents metadata 提示均为现有工程警告，本任务没有修改相关配置。

## 尚未完成的真实环境验收

以下结果不能由 focused tests 或构建成功替代：

- 499 Node 批量选择 2 台时只添加第 1 台，并最终显示 500/500。
- 500 Node 时 Classic、Professional、Group 指定添加和 Space Restore 均不得启动第 501 台 Provisioning 或地址申请。
- 500 Node、15 Switch 时可新增第 16 个 Kinetic Switch。
- 500 Node、Switch 未满时仍拒绝新增 Battery/AC Power Switch。
- 499 Node 时 Battery/AC 添加后达到 500 Node，并正确占用 8 个连续 Element 地址。
- 16 Switch 时第 17 个 Kinetic、Battery、AC 均被现有 Switch 上限拒绝。
- `space == nil` 的 Site Gateway Restore 不受 500 Space Node 限制。
- 地址不足时服务端地址申请、Provisioner 范围更新和接受批次继续添加正确。
- 500 Node 的云端上传、下载、重启、Space 切换和数据导入无截断。
- 500 Node 下 Main 加载、BLE 扫描、RSSI/Heartbeat、Group、Scene、Timed、同步任务、CPU 和内存相对 300 Node 基线可接受。

## Git 边界

本次未执行 Git commit、push 或 merge。当前 worktree 保留实施代码、测试、脚本和三份文档，等待后续真实环境验收或用户明确授权处理 Git。
