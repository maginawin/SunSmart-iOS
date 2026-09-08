# databaseReadRevision 缺失的构建修复

> 已作废：下述改绑正式 project 的方案判断错误，不应执行。用户使用 SunSmartLocal.xcworkspace 和 one-dev 开发 SDK；缺失的是 one-dev 中的源码修复。正式工程配置已恢复，正确处理见 `260908_1734_local_sdk_workflow_correction.md`。下文仅保留为错误处理的历史记录。

日期：2026-09-08。工作区：fix。

## 原因

App 的快照失效校验调用了新增的 `MeshDataManager.databaseReadRevision()`。方法存在于本次隔离 SDK 补丁中，原远端 release pin 不含该方法。上次只在 SunSmart.xcworkspace 添加了同名本地 package 覆盖，而 SunSmart.xcodeproj 仍保留远端 package 声明；命令行 workspace 构建通过，没有覆盖 project 入口及用户 Xcode 会话的依赖选择。

用户报错确认其编译所用 SDK 接口不含该方法。尚未取得该次失败的完整构建命令，不能确定用户打开了哪个入口；此次直接消除工程内两个 SDK 来源不一致的问题。

## 修改

- project 中将唯一 SDK package 改为 XCLocalSwiftPackageReference，指向 `../../nordic-sig-mesh-sdk-worktrees/site-entry-loading-sdk/nordic-sig-mesh-sdk`。
- 五个品牌的 XCSwiftPackageProductDependency 全部保留同一 package ID，并统一绑定该本地来源。
- 移除 workspace 同名覆盖 FileRef，避免依赖覆盖机制决定实际来源。
- 不再恢复 Xcode 自动移除的旧远端 Package.resolved。隔离 SDK 的原始 pin 和补丁仍由 `scripts/prepare_site_entry_sdk.sh` 管理。
- 没有删除快照版本检查，没有回退为永不失效的缓存，也没有修改 one-dev 工作树。

## 验证

- `plutil -lint SunSmart.xcodeproj/project.pbxproj` 通过。
- 解析 project 对象确认五品牌绑定同一个本地 SDK，项目无远端 package 声明；本地 SDK 确实声明 databaseReadRevision。
- `xcodebuild -resolvePackageDependencies -project SunSmart.xcodeproj -scheme SunSmart` 通过，输出明确解析到本次隔离路径，版本为 `@ local`。
- 使用 SunSmart.xcworkspace 对 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 进行 generic iOS Debug 构建，关闭代码签名；五个构建全部通过，退出码均为 0。
- `git diff --check` 通过。

本次是依赖接入修正，不改变上轮运行逻辑。原 iPad 的性能验收仍待复测。当前电脑 SDK 已准备好；其他机器需要先执行准备脚本。若已打开的 Xcode 会话仍显示旧 SDK 错误，应关闭后重新打开 SunSmart.xcworkspace，让它重新载入工程依赖。
