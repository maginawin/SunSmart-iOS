# Calibration 审查问题修复总结

## 结论

已在分析用户最新提交 `093e0743` 后完成三项审查问题修复。该提交新增的 Sensor Cal. 产品边界已完整保留：目标可达性只比较稳定的绝对 OnLux 与目标值 95% 下限，不减去 OffLux，也不重新引入暗环境能力门槛。

本次没有修改依赖配置、target、本地化或用户可见文案，没有重置、提交或推送 App 与 SDK 工作树。

## 修复内容

### 1. 按每台灯具的 Lightness Range 校验到位值

- Group 仍发送原始 Lightness 请求，不改变 Mesh 控制语义；
- 对每台必要灯具读取其 `lightnessRange`，将非零请求限制到该节点的 Low/High End Trim 后得到期望值；
- 关闭请求 `0` 始终按 `0` 校验，不受非零 Low End Trim 影响；
- Status 的 present/target Lightness 均与该节点的期望值比较；
- 到位日志增加 requested、expected、range、present、target 与 attempt，便于真机追踪不同 Trim 节点。

### 2. 消除 publish-delta 恢复计时器竞态

- 进入恢复步骤时停止上一阶段计时器；
- 移除与三次 ACK 重试并行的 30 秒恢复计时器；
- 由一个异步任务串行管理三次尝试、每次 10 秒 ACK 超时和两次 0.5 秒重试间隔；
- 仅在完整重试预算耗尽后进入失败与回滚路径，稳定保留 `publishDeltaRestoreFailed`；
- 回滚恢复同样复用显式次数、超时和间隔常量。

### 3. 取消旧 metadata 等待时恢复 continuation

- `cancelNotifyCallback` 在锁内移除匹配的 metadata callback 和原有 response callback；
- 在锁外分别用 `AccessError.cancelled` 完成所有被移除的 callback；
- 不匹配 source/opcode/destination 的 metadata waiter 保持注册；
- 避免新等待覆盖旧等待后，旧调用方因 continuation 永远不恢复而挂起。

## 回归保护

- 扩展 App 的 Sensor Calibration workflow 源码契约，覆盖逐节点 Range 期望值、publish-delta 单一路径和 callback 取消完成；
- 新增 SDK 数学测试，覆盖默认范围、High End Trim、Low End Trim、关闭值 `0`、同组不同范围和范围限制后的 Status；
- 新增 NetworkManager 测试，覆盖匹配 metadata waiter 被取消、不匹配 waiter 保留，以及被移除 response callback 收到取消结果；
- 保留最新提交中的 OnLux-only 与不含 dark-capacity gate 契约。

## 自动验证结果

- Sensor Calibration workflow contract：通过；
- Night Calibration workflow contract：通过；
- Night Calibration persistence contract：通过；
- 相关 Swift 生产代码和测试源码 `swiftc -parse`：通过；
- App 与 SDK `git diff --check`：通过；
- 使用本地 NordicSigMeshSDK、Debug、generic iOS device、关闭签名构建：
  - SunSmart：通过；
  - Archipelago：通过；
  - SLG Sync Plus：通过；
  - SylSmart：通过。

SDK 当前没有可运行的 Swift Package scheme。尝试直接用 `swiftc` typecheck XCTest 文件时，Xcode 的原始 XCTest Objective-C 头不会提供 Swift XCTest 断言符号，因此无法在当前命令行测试载体中执行这些 XCTest；这不是生产代码编译失败。新增断言已通过源码契约与语法检查，生产 SDK 代码已由四品牌构建完整编译。

## 仍需真机验收

自动验证不能替代以下 Mesh/firmware 时序验收：

1. 同一 Group 包含默认范围、High End Trim 和 Low End Trim 不同的灯具时，0%、低亮度搜索点和 100% 点均能正确到位；
2. publish-delta 三次 ACK 全部超时时，不提前回滚、不泄漏等待，最终稳定上报 `publishDeltaRestoreFailed`；
3. 同一 source/opcode 并发注册 metadata 等待时，旧调用方收到取消，新调用方仍可正常收到响应或超时；
4. Sensor Cal. 继续只按稳定 OnLux 与目标 95% 下限判断可达性。

## 工作树边界

App 仓库当前分支相对远端 ahead 2，保留用户提交；本次新增 App 契约、检查脚本参数和两份 `docs/` 文档。SDK 仓库在本次开始前已有多文件未提交改动，本次仅聚焦修改校准管理器、NetworkManager callback 取消逻辑及对应测试，没有处理或归并其他脏文件。
