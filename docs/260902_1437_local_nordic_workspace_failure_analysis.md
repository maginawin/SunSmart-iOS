# Local NordicSigMeshSDK Workspace 配置失败分析

## 结论

`scripts/setup_local_nordic_sdk_workspace.sh` 失败在生成 `SunSmartLocal.xcworkspace` 之前的共享依赖校验阶段。

直接失败条件是：

```text
FAIL: Package.resolved does not record the release branch.
```

根因是 2026-09-01 的提交 `2e44563a` 将主 App 使用的 `NordicSigMeshSDK` 依赖要求从 `release` 分支改成固定 revision `86f5ec9e40148b9cd93e0512702337fcec41dd40`，但 2026-08-27 引入的 `scripts/check_nordic_sdk_dependency.sh` 仍强制要求 `Package.resolved` 包含 `"branch" : "release"`。依赖策略变更后，配套校验脚本和 README 没有同步更新。

## 执行路径

setup 脚本依次执行：

1. 检查本地 SDK 是否包含 `Package.swift`。
2. 解析本地 SDK 真实路径，并检查它是否为 Git worktree。
3. 执行 `scripts/check_nordic_sdk_dependency.sh`。
4. 只有前置检查通过后，才创建 `.local-sdk/`、`SunSmartLocal.xcworkspace/` 和 workspace 内容。

当前第 3 步退出，因此 `SunSmartLocal.xcworkspace` 不会生成。这不是 workspace XML 写入失败，也没有进入 Xcode Swift Package 解析阶段。

## 证据

- 原 setup 命令稳定返回退出码 1，并输出 `Package.resolved does not record the release branch`。
- 当前 `Package.resolved` 只记录 revision `86f5ec9e40148b9cd93e0512702337fcec41dd40`，不再记录 branch。
- 提交 `2e44563a` 明确把 `project.pbxproj` 中主引用从 `kind = branch; branch = release;` 改为 `kind = revision; revision = 86f5ec9...;`，同时删除 `Package.resolved` 中的 `branch` 字段。
- 校验脚本来自更早的提交 `9d9132b4`，仍执行 `grep -Fq '"branch" : "release"'`。
- 本地 SDK 路径存在、包含 `Package.swift`、是 Git worktree；`.local-sdk/nordic-sig-mesh-sdk` 也已正确指向该目录。
- 当前本地 SDK 的 `HEAD`、本地 `release` 和 `origin/release` 均解析为 `86f5ec9e40148b9cd93e0512702337fcec41dd40`，与 App 固定 revision 一致。

## 校验脚本的附带缺陷

当前工程中仍有另一条供 Lumineux 使用的 `NordicSigMeshSDK` package reference，要求 `release` 分支；主 App 的四条 product dependency 使用另一条固定 revision 引用。

校验脚本只在整个 `project.pbxproj` 中搜索任意 `branch = release;`，因此会被 Lumineux 的分支引用满足；随后它又统计主 App 固定 revision 引用的四个 product dependency。两项检查没有约束同一个 package reference，导致前半段误判通过，直到检查 `Package.resolved` 才暴露冲突。

## 修复方向

需要先确认共享依赖的目标策略：

1. 如果保留主 App 固定 revision，应更新校验脚本和 README，使其按实际生效的 package reference 校验 `kind = revision`，并验证 `project.pbxproj` 与 `Package.resolved` 的 revision 一致；同时单独校验 Lumineux 的分支引用。
2. 如果所有 target 都应继续跟随 `release` 分支，则应恢复主 App package reference 和 `Package.resolved` 的 branch 语义，而不是绕过校验。

不建议只删除 `Package.resolved`、手工补写 `branch` 字段或注释掉失败断言；这些做法会掩盖 `project.pbxproj` 中实际使用固定 revision 的事实。

## 验证边界

本次只复现并分析前置脚本失败，没有修改脚本、工程依赖或运行 iOS 构建。由于执行在 workspace 创建前已经终止，当前没有证据表明 Xcode 构建或本地 Package override 本身存在故障。
