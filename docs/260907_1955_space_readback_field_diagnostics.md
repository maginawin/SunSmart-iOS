# Space 回读字段级差异日志

## 本轮范围

按用户要求，先补脱敏诊断，等待现场日志再判断实际差异。本轮没有修改配置比较规则、上传策略、冲突处理或恢复状态，也没有清理待确认记录。

修改 `SpaceConfigurationIntegrityPolicy.swift` 和 `SpaceConfigurationSafety.swift`，在原直接回读与持久提交恢复回读发生 mismatch 时，调用同一套诊断。补充 `SpaceConfigurationIntegrityPolicyTests.swift` 的覆盖。

## 日志内容

| 标记或字段 | 含义 |
| --- | --- |
| `[SpaceConfigurationReadback]` | 本次比较上下文、远端版本、两侧设备数量及增减设备身份摘要 |
| source=direct / resume | 直接回读 / 持久提交恢复回读 |
| submissionId、phase、submitted、attempt | 恢复路径的提交 ID、prepared/accepted/verified 阶段、提交版本、尝试次数 |
| localTimestamp | 当前 Space 本地修改版本，用于发现待确认提交是否落后于本地 |
| remoteTimestamp | 本次响应版本；不存在则明确记录 missing |
| `[SpaceConfigurationDiff]` | 对真正参与比较的配置 Data 进行结构差异诊断 |
| submittedSHA256、remoteSHA256 | 配置 Data 的 SHA-256 前 8 字节，以 16 位十六进制显示 |
| path | 配置路径，例如 $.memberships[0].groupState、$.triggerZones[0].items[0].deviceAddress |
| submitted / remote | 字段两侧的类型及允许显示的值；区分 missing、null、array、object、number、bool、string |
| differencesShown、scanLimited | 已输出差异数，以及扫描是否达到限制 |

比较对象仍为原有的 memberships、非虚拟 Group Profile / Path、Space Trigger Zones。数组位置保持现有比较语义，不排序或修正实际配置。

最多输出 24 项差异，遍历限制为 4096 个位置、16 层深度。相同容器直接跳过。容器新增、删除或类型变化显示类型与数量；双方都有的容器继续下探。`scanLimited=true` 表示日志并不包含所有差异，不能以未显示推断其他字段一致。

## 脱敏边界

- 新诊断从参与比较的逻辑配置出发，不打印完整请求/响应，也不包含顶层密码、NetKey、AppKey、设备 Key 等非比较字段。
- 设备 UUID、任意文本值显示长度或 SHA-256 摘要，设备增减列表也使用摘要。
- 允许显示固定四位十六进制地址/场景编号，以及已知配置字段的数值、布尔值。
- 未知字段名转为摘要；未知字段分支中的值不会因嵌套了已知字段名而恢复明文输出。
- Site / Space ID 和提交 ID 继续用于关联同一次操作。
- 本轮仅保证新增诊断按以上规则输出，没有改造已有 HTTP 完整 body 日志。

## 下次复现的采集步骤

1. 编译运行包含本轮改动的 App，进入此前失败的 Site / Space。
2. 触发一次同步；若自动同步已输出完整一轮结果，无需重复点击。
3. 提供这一轮从 `[SpaceConfigurationReadback]` 开始，到 `[SpaceConfigurationSafety] blocked` 结束的日志，包含全部 `[SpaceConfigurationDiff]` 行。恢复路径通常有 attempt=1、2、3 三组。
4. 不需要提供完整 HTTP body。保留 source、submissionId、phase、版本、摘要及 scanLimited 字段，便于判断是否反复比较同一提交，以及云端结果是否变化。

字段路径来自实际比较配置，可据此区分真实成员/拓扑差异与表示差异；本轮合成样例不能代替该手机的现场证据。

## 验证

- 生产比较策略测试：缺省与空数组、缺省与 null、数值与字符串、数值与布尔值、数组顺序、持久提交入口与直接入口输出一致性，全部通过。
- 隐私测试：在节点、认证字段及可透传扩展字典内注入敏感文本、未知字段名、嵌套数值，验证不输出原文；验证差异数量限制和仅观测字段变化不产生差异。
- `python3 scripts/check_space_recovery_receipts.py` 通过，实际生产恢复方法的三轮 mismatch 均输出新日志；持久化、权限与生命周期原有断言继续通过。
- SunSmart Debug generic iPhoneOS 无签名构建通过，退出码 0；编译输出仍包含既有资源、弃用 API、并发及未使用返回值警告。
- `git diff --check` 通过。未更改资源、本地化、target 或依赖配置，未运行 Simulator，未执行生产接口或真机验收。
