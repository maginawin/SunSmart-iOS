# App 与 SDK 更新审查

## 结论

未发现本次差异引入、证据充分且需要提出的缺陷，审查 findings 为空。本结论针对当前 App 与本地 SDK 的组合，不代表真实设备和服务器验收完成。

## 范围

- App：`fix-warning` 当前已跟踪差异及新增测试、脚本、资源；基线 `a4ee57d3379b8e4fb9f9c71e8d546a44562820ca`。
- SDK：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev` 当前 6 个修改文件及 2 个新增测试；基线 `9a122b9cb1405e875ae7aeb26fa11e486bed05be`。
- 核对根目录与适用目录指引，重点沿 Operation/Remote Send、云授权、扫码照片、按钮调用点、资源及本地化引用检查。
- 没有修改业务代码或 SDK，没有提交、重置或清理工作树；本文件为审查新增记录。

## 本轮实际验证

| 检查 | 结果 |
| --- | --- |
| `check_warning_regressions.py`，显式传入 one-dev SDK | 通过：Operation 并发完成/取消与重入、Remote Send 重试和晚到回调、照片请求状态、MAC 格式、云授权取消/替换及 generation |
| `check_network_response_queue.py` | 通过：两种生产适配器后台解析与主线程回调 |
| `LBXScanWrapperThreadingContractTests` | 通过：session 生命周期串行队列静态契约 |
| `check_nordic_sdk_dependency.sh` | 通过：共享依赖配置及 target 引用契约 |
| `check_wifi_gateway_proxy_ready_no_time_set.sh` | 通过：五 target 源码成员及 Proxy Ready 契约 |
| 英中 Localizable.strings 的 plutil 检查 | 通过 |
| Dongle 改名资源与 HEAD 原资源逐字节对比 | 通过 |
| App 与 SDK 的 `git diff --check` | 通过 |

通过直接运行 xcodebuild，重新验证 `SunSmartLocal.xcworkspace` 的以下五个 scheme：SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux，全部 BUILD SUCCEEDED。配置为 Debug、iphoneos、generic/platform=iOS、CODE_SIGNING_ALLOWED=NO，使用已有构建缓存；未使用 Simulator、shell 包装或日志重定向。

## 验证边界

- 本轮构建使用本地 SDK，不是共享远程 release 依赖的发布兼容性验证。
- 本轮没有重新执行真机 UI 测试，没有连接真实服务器或进行 BLE/Mesh Remote Provisioning 验收。
- 生产代码注入式行为测试和静态契约不能替代真实网络、相机时序、完整业务页面或 iPad 布局验收。
- 既有实施记录中的真机结果与待验收事项见 `260908_1959_warning_fix_results.md`；未将其中历史结果算作本轮重新执行。
