# Xcode Build 失败诊断

## 结论

当前源码可以正常编译。本次 Xcode 失败由旧工程状态与并发构建共同触发，不是 Edit Site 改动产生的 Swift 编译错误。

## 日志证据

近期 Xcode activity log 中存在两条错误：

1. Build input file cannot be found：旧路径 `SunSmart/Main/Device/Gateway/Model/WiFiGatewayTimeSyncCoordinator.swift`；
2. `build.db` 被锁定，并明确提示可能有两个构建同时使用同一 DerivedData。

失败日志对应的 destination 为 `MtestiPhone15`。

## 根因

`time-zone` 分支的 `2da63abc` 已删除 `WiFiGatewayTimeSyncCoordinator.swift`，并在 `project.pbxproj` 中把原有 PBX 引用切换为 `WiFiGatewayAutomaticLoadGate.swift`。当前磁盘上的工程配置正确，已经不再引用被删除文件。

Xcode 仍尝试编译旧路径，说明打开的 workspace/build description 尚未重新加载最新 `project.pbxproj`。同时命令行 `xcodebuild` 与 Xcode GUI 使用了同一个 DerivedData，导致 `build.db` 锁竞争。

## 当前验证

停止前一轮构建后，直接使用当前 workspace、SunSmart scheme、Debug、generic iPhoneOS、关闭签名重新构建，结果为 `BUILD SUCCEEDED`，退出码 0。

## 建议恢复步骤

1. 确认 Xcode 和终端中没有仍在运行的 SunSmart build；
2. 在 Xcode 中关闭当前 workspace；
3. 重新打开 `/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/time-zone/SunSmart.xcworkspace`，强制重新读取 `project.pbxproj`；
4. 执行 Product → Clean Build Folder；
5. 再选择原设备 `MtestiPhone15` 构建。

若仍出现同一旧文件路径错误，再删除当前 workspace 对应的 DerivedData 后重试；删除 DerivedData 只清理可再生构建缓存，但应在确认没有其他构建运行后执行。

## 范围

本次诊断没有修改生产代码、工程配置、依赖或 SDK，只新增本诊断文档。
