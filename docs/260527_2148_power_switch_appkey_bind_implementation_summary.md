# Power Switch AppKey Bind Implementation Summary

## 结论

- 已在本地 `NordicSigMeshSDK` 中通过 PID 统一识别 Battery / AC Power Switch：
  - Battery：`0x2A01`、`0x2A02`
  - AC：`0x2A11`、`0x2A12`
- 共同按键 Client Models 已改为同一套 all-elements 收集与 AppKey bind 支持逻辑。
- Battery Server 只在 Battery Power Switch PID 下作为额外 required model；AC Power Switch 不要求 Battery Server。
- 添加流程中 required model 的 key bind 失败判断已从 Battery-only 改为 Power Switch 统一判断，因此 AC Power Switch 关键 app key bind 失败会走添加失败。

## 共同绑定的 Client Models

| Model ID | Model 名称 |
| --- | --- |
| `0x1001` | Generic OnOff Client |
| `0x1003` | Generic Level Client |
| `0x1205` | Scene Client |
| `0x1302` | Light Lightness Client |
| `0x1311` | Light LC Client |

## SDK 提交

- `ab537ba` `test: cover power switch appkey bind models`
- `9cfff7a` `feat: bind power switch profile models by pid`
- `9c600ce` `fix: require power switch appkey bind completion`

## 验证

用户要求不使用模拟器校验，因此未继续运行 simulator tests。已完成以下设备 SDK 编译验证：

- `xcodebuild -project NordicSigMeshDemo/NordicSigMeshDemo.xcodeproj -scheme NordicSigMeshSDK -configuration Debug -sdk iphoneos -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO build`：通过
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO build`：通过
- `xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO build`：通过
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO build`：通过
- `xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO build`：通过

## 真机重点验证

- AC Power Switch 添加成功后，确认 5 个共同 Client Models 的所有 element 都绑定当前 AppKey。
- Battery Power Switch 添加成功后，确认同样的 5 个共同 Client Models 绑定当前 AppKey，且 Battery Server 仍被绑定。
- AC Power Switch 不应因为缺少 Battery Server 被判定为 required configuration 不支持。
- 任一共同 Client Model 的 required AppKey bind 失败时，AC / Battery Power Switch 都应添加失败。
