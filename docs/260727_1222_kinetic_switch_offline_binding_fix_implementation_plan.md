# Kinetic Switch 离线解绑残留修复实施计划

## 目标

修复 proxy 离线解绑失败后删除 Switch 误判为无同步任务的问题，并允许原 proxy 节点覆盖接管残留绑定，同时继续阻止其他 proxy 形成双绑定。

## 实施范围

1. 新增 Foundation-free 的纯策略：
   - 合并当前和待解绑 Group 地址；
   - 合并当前和待删除 proxy 地址；
   - 判断扫码绑定应正常继续、由原 proxy 接管，还是拒绝已有绑定。
2. 删除 Switch 的同步规划覆盖：
   - `bindGroupAddresses + unbindGroupAddresses`；
   - `proxyNodeAddress + deleteProxyNodeAddress`。
3. 同一 Switch 同时存在当前 proxy 和待删除 proxy 时，两者都进入删除任务。
4. 扫码检测到旧 MAC：
   - 旧绑定节点等于当前选择 proxy，且没有其他 Switch 拥有该绑定：允许接管；
   - 其他情况继续拒绝。
5. 修正删除缓存时的空 MAC 匹配，不允许 `nil == nil` 命中无关节点。

## TDD

聚焦测试：

`Tests/Device/KineticSwitchBindingPolicyTests.swift`

RED 已确认：策略类型不存在时，`swiftc` 报告 `cannot find 'KineticSwitchBindingPolicy' in scope`。

GREEN 命令：

`swiftc -parse-as-library SunSmart/Main/Device/Switches/Model/KineticSwitchBindingPolicy.swift Tests/Device/KineticSwitchBindingPolicyTests.swift -o /tmp/KineticSwitchBindingPolicyTests`

随后执行测试二进制并检查 exit code。

## 集成验证

1. 检查新增策略文件同时属于四个共享品牌 target。
2. 运行聚焦策略测试。
3. 运行 `git diff --check`。
4. 使用 generic iPhoneOS、关闭签名依次构建：
   - SunSmart
   - Archipelago
   - SLG Sync Plus
   - SylSmart
5. 保存实施总结，明确真机 Mesh 尚需验证离线、重新上线和原 L1 覆盖接管。

## 边界

- 不修改 SDK。
- 不新增本地化文案或 UI 页面。
- 不修改 Kinetic switch QR、按键动作、虚拟组协议或 CCT 修复。
- 不允许旧绑定在 L1 时直接选择其他 proxy。
