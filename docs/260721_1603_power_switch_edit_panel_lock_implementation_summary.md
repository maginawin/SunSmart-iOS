# Battery/AC Power Switch Edit Panel 锁定实施总结

## 实施结果

独立 Edit Switch 页面已按方案 A 完成调整：

- Virtual Battery/AC power switch 保留 Panel 右侧箭头，并在具备 edit 权限时允许进入 Select Panel。
- Real Battery/AC power switch 保留当前 Panel 值，隐藏右侧箭头，并禁止进入 Select Panel。
- Panel 行同时具备 UI 交互禁用和跳转入口 guard 两层保护。
- Virtual 设备完成 LINK 后，现有编辑数据刷新链路会重新应用 Panel 行状态。
- 隐藏箭头时，Panel 值使用普通只读信息行的右侧间距，不保留箭头占位。

## 修改范围

业务改动仅涉及：

- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchInfoRowView.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`

未修改 Group Power Switch 页面、Select Panel 页面、ViewModel、Model、Repository、数据库、本地化、资源、target、依赖、协议或 NordicSigMeshSDK。

## 提交记录

- 设计：`2bbbda54 docs: add power switch edit panel lock design`
- 计划：`de95af0e docs: add power switch edit panel lock plan`
- 业务实现：`c749eda9 fix: lock real power switch panel selection`

## 验证结果

- 改动前源码基线：确认动态箭头和真实设备 Panel 保护不存在。
- 改动后定向源码断言：通过。
- 非目标文件差异检查：无差异。
- `git diff --check`：通过，无输出。
- SunSmart Debug iPhoneOS 构建：通过，输出 `** BUILD SUCCEEDED **`。

构建命令：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 尚未执行的运行时验收

当前会话没有可用真机及对应 Virtual/Real Battery/AC 测试数据，因此以下行为未在运行时操作验证：

- Virtual Battery/AC 点击 Panel 并选择类型。
- Real Battery/AC 点击 Panel 无跳转。
- Virtual Battery/AC 完成 LINK 后页面即时切换为只读状态。
- Create Battery/AC 与 Group Power Switch 页面回归。

以上项目需要在具备对应设备和数据的环境中继续验收；编译成功不替代运行时行为验证。

## 工作区说明

现有未跟踪文档 `docs/260721_1147_site_creation_time_timezone_analysis.md` 与本需求无关，实施过程中未修改、未暂存、未提交。
