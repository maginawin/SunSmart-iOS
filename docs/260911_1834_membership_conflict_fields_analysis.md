# 回读冲突属性定位：Space 1 单设备缺失

## 确认的冲突字段

用户本轮日志中的目标是新 Site `A0DA308F-8EB3-447E-B86F-C12927E0D657` 下的 Space 1 `8BB0860C-6346-4D60-8153-8184CCDA30A9`，与上一轮 Space 3 的作用域不同。

| 比较路径 | 提交记录 | 远端回读 |
| --- | --- | --- |
| `$.memberships.count` | 1 | 0 |
| `$.memberships[0]` | 含 3 个属性的对象 | 整个对象缺失 |

`memberships` 是 App 从原始 `nodes` 提取的逻辑配置，并非接口原始字段名。本轮完整 HTTP 响应明确显示 `nodes=[]`，所以缺失已出现在响应正文，不能归因为后续设备导入或 UI 过滤。

## 属性范围与日志边界

依据 `SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift` 的 `configurationData`，每个成员最多提取 `uuid`、`unicastAddress`、`groupAddress`、`groupState` 四个属性。空字符串 `groupAddress` 会被规范化移除。

`object(count=3)` 只表示本地规范化成员对象有 3 个键，不表示三项属性的值被服务器改写。远端连成员对象都没有，因此当前直接冲突是节点成员缺失。

差异函数遇到 object 与 missing 类型不一致时，记录对象级差异后立即返回，不展开对象内部。因此本日志不能确定这三个键的完整名单及各自值，尤其不能从 count=3 单独断言缺少的是哪一个可选字段。

`differencesShown=2 scanLimited=false` 表明这次逻辑配置差异扫描未达到数量或深度限制；比较范围内只有上述两条差异，没有 Group/Profile 或 Trigger Zone 差异。这不表示全部原始响应字段均被比较。

## 不直接参与本次冲突的字段

- `deviceCount=1` 与 `nodes=[]` 不一致，是远端统计与明细矛盾的证据；`deviceCount` 不在逻辑配置比较对象中。
- 提交、本地和远端 `updateTimestamp` 都为 `1789122818`；时间戳相等无法抵消设备成员缺失。
- AppKey、NetKey、设备运行缓存等不在本次逻辑配置比较范围。
- `The bearer is closed` 表示日志中的 Mesh 发送遇到关闭的承载；没有证据显示它导致 HTTP 响应中的节点缺失。开头发送日志使用 Space 3 密钥名，而回读目标是 Space 1，不能只凭相邻日志将两者认定为同一操作链。

## 与上一轮日志的关联

两次缺失 UUID 的哈希均为 `e9cc8a9876f5e7ae`，强烈指向同一个设备 UUID 在不同 Site/Space 中反复缺失。上一轮该 UUID 对应地址 `0023`，但本轮没有打印地址，不能假定重新配网后的地址仍然相同。

这提高了服务端设备 UUID 唯一性约束、旧归属、跨 Site/Space 更新或查询过滤问题的排查优先级，但不能据此证明具体根因。若要确定哪个上传属性触发服务端遗漏，需要原始上传节点对象、写入结果和查询链证据；本次日志仅足以确定导致 App 判定冲突的比较字段。

本次仅分析日志和核对源码，新增文档，未修改业务代码或运行设备测试。
