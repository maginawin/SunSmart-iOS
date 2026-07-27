# Kinetic Switch 离线解绑与残留绑定修复总结

## 结论

已按确认的方案 B 完成修复，并结合“L1 重新设置为 Proxy 时会覆盖旧 Switch MAC”的补充信息简化历史异常数据的恢复逻辑。

修复同时覆盖两个层面：

1. 正常删除流程不再遗漏已进入待删除状态的组和 Proxy，避免同步计划为空后发生仅删除 App 本地对象、Mesh 配置仍残留的问题。
2. 对已经形成的历史残留数据，允许用户继续选择原 Proxy 节点并重新扫描、覆盖旧 Switch MAC；若残留绑定位于其他 Proxy，或仍由另一个 Switch 对象持有，则继续阻止绑定。

## 根因

解绑操作会先把当前关联移动到待删除字段：

- 组：从 `bindGroupAddresses` 移动到 `unbindGroupAddresses`
- Proxy：从 `proxyNodeAddress` 移动到 `deleteProxyNodeAddress`

但原删除计划只读取当前关联字段，并从当前绑定组的节点中反查 Proxy。因此离线解绑失败后再次删除时，待删除组和旧 Proxy 都可能没有进入同步计划，最终造成：

- App 中的 Switch 对象被删除；
- Proxy 节点仍保存旧 Switch MAC 和按键配置；
- 目标灯具仍保留原订阅；
- 后续扫码命中旧 MAC 后被判定为“已经绑定”。

## 实现内容

### 1. 删除计划合并当前与待删除关联

删除 Kinetic Switch 时：

- 组清理目标使用当前绑定组与待解绑组的并集；
- Proxy 清理目标使用待删除 Proxy 与当前 Proxy 的并集；
- 地址去重，并保留待删除 Proxy 优先的执行顺序；
- 支持在一次删除流程中清理多个可能的 Proxy 节点。

这样即使用户先执行过失败的解绑保存，后续删除仍能得到完整的 Mesh 清理计划，不会因为当前字段已被清空而误判为无需同步。

### 2. 删除成功后的本地 Proxy 状态清理

本地删除 Switch 对象时，只处理地址明确属于该 Switch 的 Proxy，并且仅在 MAC 一致时清空：

- `enOceanMacAddress`
- `enOceanProxySwitchKeys`

不再通过可空 MAC 的全局比较误命中无关节点。

### 3. 历史残留绑定恢复

扫码检测到相同 Switch MAC 已存在时：

- 检测节点就是用户当前选择的 Proxy，且没有其他 Switch 对象持有该关联：允许继续绑定，由现有 SDK 配置流程覆盖旧 MAC/Key 配置；
- 检测节点不是当前选择的 Proxy：继续提示已绑定；
- 仍有其他 Switch 对象持有该 Proxy 与 MAC：继续提示已绑定。

因此历史异常数据无需再通过“把 L1 从 Space 删除后重新添加”才能恢复。

### 4. 多品牌 target

新增的纯策略文件已加入以下 target：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

本次没有修改本地 `NordicSigMeshSDK`。

## 自动化验证

### 聚焦策略测试

覆盖：

- 当前组与待解绑组的合并、去重；
- 当前 Proxy 与待删除 Proxy 的合并、去重和顺序；
- 未绑定扫码；
- 原 Proxy 残留绑定接管；
- 其他 Switch 持有时拒绝；
- 选择不同 Proxy 时拒绝。

结果：通过，输出 `KineticSwitchBindingPolicyTests passed`。

### 工程与差异检查

- `SunSmart.xcodeproj/project.pbxproj`：`plutil` 校验通过；
- `git diff --check`：通过。

### iPhoneOS 编译

使用 Debug、generic iPhoneOS、关闭签名验证，以下 scheme 均编译成功：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

编译日志仍包含工程既有的资源重名、重复 Build File、旧 API 和 Main Actor 等 warning，本次改动未新增编译错误。

## 真机 Mesh 验收清单

自动化测试与编译不能替代真实 Mesh 状态验收，建议至少验证：

1. L1 在线，正常绑定 Switch 与组，控制功能正常。
2. L1 离线，取消 Proxy 并保存失败，再取消组并保存失败。
3. 直接删除 Switch：应显示旧 Proxy 和旧组的待清理任务，不应本地静默删除成功。
4. L1 恢复在线后重试同步/删除：Proxy MAC、按键配置和灯具订阅均应清理，随后 Switch 对象才删除。
5. 使用原 L1 创建并绑定新的 Switch：应允许扫码并由 SDK 覆盖旧配置。
6. 使用其他 Proxy 扫描仍残留在 L1 上的 MAC：应继续提示已绑定。
7. 如果另一个有效 Switch 对象仍持有该 Proxy/MAC：应继续提示已绑定。
8. 删除失败后退出页面、重新进入 App，再执行同步/删除，待删除数据仍应保留且行为一致。

