# Xcode 构建数据库锁冲突分析

2026-09-08 11:33 只读检查结果：报错指向 SunSmartLocal 的 DerivedData 构建数据库，而非 App 业务数据库。

## 当前证据

`lsof` 显示两个构建服务同时打开以下文件：

`/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmartLocal-dibzjtxwzdtcnqdwjaapuemjfonu/Build/Intermediates.noindex/XCBuildData/build.db`

| 服务 PID | 上级进程 | 来源 |
| --- | --- | --- |
| 11763 | xcodebuild 11745 | 后台 SunSmartLocal.xcworkspace / SunSmart / Release / generic iPhoneOS 构建 |
| 94903 | Xcode 94822 | Xcode 图形界面的构建服务 |

后台 xcodebuild 的上级为另一终端会话的进程 5376。本轮执行只读检查的会话进程为 8397。

两个服务打开同一数据库，加上用户提供的锁冲突报错，说明当前存在 GUI 与后台命令行构建共享构建目录的争用。文件打开信息本身不能区分报错瞬间哪一个服务持有写锁。

此前本对话执行的五品牌 Debug 构建均已结束，使用的是 SunSmart.xcworkspace，其 DerivedData 为 SunSmart-dzyljvihefrinmercupzevgsnzly，与此次报错的 SunSmartLocal 目录不同。

## 处理建议

优先等待后台构建正常结束，再在 Xcode 重试。同一 DerivedData 目录应串行构建；若确需 GUI 与命令行同时构建，为命令行任务指定独立的 DerivedData 目录。切换 Debug/Release 或 scheme 不足以隔离同一个构建数据库。

该错误不表明 Swift 源码错误，也不表明 App 的 Group/Profile 数据库保存失败。本轮没有停止任何进程、删除 build.db 或清理 DerivedData。
