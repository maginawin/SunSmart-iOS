# Kinetic Switch Proxy 删除事务修复总结

## 结论

本次修复将 Kinetic Switch Proxy 的本地关联从“用户保存时立即清除”调整为“Mesh 解绑成功后提交清除”。当 Proxy 节点离线或 Mesh 操作失败时，App 保留当前 Proxy 地址、Switch MAC、Security Key 和待删除地址，使失败状态可以重试，也避免出现界面显示未绑定但设备仍保留旧绑定的状态分裂。

节点从 Space 删除属于不可重试的终止路径，此时按节点地址直接清理所有 Switch 的当前和待删除 Proxy 引用。

## 原因确认

原流程在用户取消 Proxy 或修改 Switch 关联时，先把本地当前 Proxy 字段清空，再进入 Mesh 同步。若 Proxy 离线导致解绑失败：

- Mesh 节点仍保存旧 Switch MAC；
- App 已丢失当前 Proxy、MAC 和 Key；
- 后续删除 Switch 只能根据残缺的本地关系生成任务；
- L1 上线后会继续报告旧绑定，而 App 界面已经无法表达和重试该绑定；
- 只有从 Space 删除 L1 才会清除残留状态。

因此问题不是单一的删除失败，而是本地状态提交时机早于 Mesh 事务结果，造成 App 与节点状态失配。

## 实施内容

### 1. Proxy 保存与解绑事务

- 取消当前 Proxy 时，不再立即清空当前地址、MAC 和 Key。
- 保存为“当前 Proxy 与待删除 Proxy 指向同一节点”的可重试状态。
- Mesh 解绑成功后，才清除当前 Proxy、待删除 Proxy、MAC 和 Key。
- Mesh 解绑失败时不提交清理，完整保留原关联。
- L1 → L2 替换时，保留 L2 为当前 Proxy，同时将 L1 记录为待删除 Proxy。
- 旧 Proxy 删除步骤成为新 Proxy 配置步骤的前置条件；旧删除失败时不会继续配置新 Proxy。
- 存在另一个尚未清理的待删除 Proxy 时，拒绝覆盖并复用现有提示。

### 2. Switch 删除与 Proxy 扫描

- 删除 Switch 时同时覆盖当前和待删除组、当前和待删除 Proxy，避免只处理活动关系。
- 只有整个同步成功后才删除 Switch 对象；任一 Proxy 或组清理失败时保留 Switch 数据。
- 原 Proxy 节点重新作为所选 Proxy 扫描同一个面板时，允许利用节点会覆盖旧 Switch MAC 的固件行为恢复绑定。
- 若该节点和 MAC 仍被另一个 Switch 明确占用，继续阻止绑定。

### 3. Space 删除节点

- 节点执行 Space 删除扩展清理时，遍历所有 Switch。
- 当前 Proxy 地址匹配时，清除地址、MAC 和 Key。
- 仅待删除 Proxy 地址匹配时，只清除待删除引用，保留新的当前 Proxy。
- 同一异常节点被多个 Switch 引用时全部处理。

### 4. Group Members 移除 Proxy 节点

- 在修改节点 `groupState` 或 Switch 数据前完成整批原子预检。
- 受影响时显示一次确认：
  - English: `One or more selected devices are being used as switch proxies. Removing them from the group will also unbind the corresponding switch proxies.`
  - 简体中文：`一个或多个所选设备正在作为开关代理。从组中移除这些设备也会解除对应的开关代理绑定。`
- 用户取消时不写入任何 Proxy 或组状态。
- 用户继续后仅写入待删除 Proxy，保留当前 Proxy、MAC 和 Key。
- 退组节点不再生成重新绑定 Proxy 或 Switch 虚拟组订阅的任务。
- 真实组退订继续依赖 Proxy 和 Switch 虚拟组清理；任一清理失败时，真实退组不会执行。
- 失败的 Proxy 子步骤进入同步状态聚合，后续仍可选择并重试。

## 自动化与静态验证

- `KineticSwitchBindingPolicyTests`：通过。
- `KineticSwitchProxyTransactionContractTests`：通过。
- 两个新增边界均执行了 RED → GREEN：
  - Proxy 替换缺少“旧删除成功后才能配置新 Proxy”的依赖；
  - Proxy 子步骤未进入失败状态聚合，无法可靠重试。
- `plutil -lint`：
  - `SunSmart.xcodeproj/project.pbxproj`：OK。
  - English `Localizable.strings`：OK。
  - 简体中文 `Localizable.strings`：OK。
- `git diff --check` 与 `git diff --cached --check`：通过。
- 新增策略文件已加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 Target。

## iPhoneOS 构建结果

以下构建均使用 generic iPhoneOS、Debug、`CODE_SIGNING_ALLOWED=NO`：

- SunSmart：`BUILD SUCCEEDED`
- Archipelago：`BUILD SUCCEEDED`
- SLG Sync Plus：`BUILD SUCCEEDED`
- SylSmart：`BUILD SUCCEEDED`

构建日志仍包含工程既有的资源命名、旧 API 和 Swift actor 隔离警告，本次修改未引入编译错误。

## 仍需真机 Mesh 验收

1. L1 在线正常绑定 Switch，关闭 L1 后取消 Proxy 并保存：
   - 同步失败；
   - 当前 Proxy、MAC、Key 仍显示和保存；
   - 待删除 Proxy 为 L1；
   - 重新进入后可以重试。
2. L1 恢复在线后重试：
   - 解绑成功；
   - 当前和待删除 Proxy、MAC、Key 同步清空；
   - Switch 图标与绑定页状态一致。
3. L1 离线时删除整个 Switch：
   - 同步失败；
   - Switch 对象和全部关联保留；
   - L1 上线后可继续删除。
4. 从 Space 直接删除 L1：
   - 所有引用 L1 的当前或待删除 Proxy 均被清理；
   - 仅待删除 L1 时不影响新的当前 Proxy。
5. Group Members 移除 L1：
   - Cancel 不改变任何状态；
   - Continue 先解绑 Proxy，再退出真实组；
   - Proxy 解绑失败时真实组退订不执行；
   - 重试成功后完成退组。
6. L1 → L2 替换：
   - L1 删除失败时不配置 L2；
   - L1 删除成功后才配置 L2；
   - 配置 L2 失败时保留 L2 当前关联，并可单独重试。
7. 使用原 L1 重新设置为 Proxy 并扫描同一面板：
   - 允许覆盖 L1 上旧 Switch MAC；
   - 若确实被另一个 Switch 占用则继续提示已绑定。

## 范围说明

- 未修改 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`。
- 未新增第三方依赖或 Auth 信息。
- 未执行 Git commit、merge、push 或 reset。
- 保留工作区中已有的其他修改与文档。
