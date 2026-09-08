# 后台构建结果安装保留 STOP 状态

## 修复结果

修复 `SyncDevicesViewController.installTaskPlan` 在用户 STOP 后被迟到构建结果恢复为 `.inSync` 并自动启动的问题。

- 只有当前状态仍为 `.inSync` 时，才接受构建结果的初始状态；构建失败仍能阻止自动启动。
- 当前已为 `.syncFailure` 时保留该状态，并将新安装模型标记为已结束、失败，使设备可被选择并通过现有流程手动重试。
- 保留离页后拒绝结果安装、HUD 收尾、错误提示和列表刷新行为。

生产改动仅涉及安装方法；未修改 SDK、依赖、target、资源、本地化或布局约束。

## 回归证据

新增可控队列用例：结果排队后先模拟 STOP，再交付结果。修复前运行失败，断言为 `late plan must preserve STOP and must not automatically restart`；修复后通过。

新增 Session 集成用例使用生产安装方法、生产任务模型及真实 Session 的 `stop()`、选择失败设备、重试准备与执行流程，验证：

1. STOP 发生于任务安装前，迟到安装不发送配置且保持 `.syncFailure`。
2. 新安装设备与任务变为可重试状态。
3. 用户选择设备并主动重试后才发送配置，模拟成功响应后同步成功。

UI 容器、传输及协议输入使用测试替身；该证据不代表真机 BLE/Mesh 或 UIKit 交互验收。

## 验证结果

- `python3 scripts/check_sync_run_lifecycle.py`：通过，包含新增竞态、正常安装、构建失败等待重试及离页拦截。
- `python3 scripts/check_sync_execution_session.py`：通过，包含新增安装后手动重试和既有 Session/Coordinator 回归。
- `python3 scripts/check_sync_task_builders.py`：通过。
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`：`BUILD SUCCEEDED`。
- `git diff --check`：通过。

测试替身仍有不可达 default 编译警告；本次未进行其他品牌构建或真机验证。未提交 Git，保留已有审查与建议文档。
