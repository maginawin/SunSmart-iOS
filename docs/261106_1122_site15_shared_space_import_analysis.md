# Site 15 分享 Space 1 后提示成功但列表不可见：原因分析

最新状态（2026-11-06）：用户已确认下方字段语义及 demo，坐标解析失败置空已实施；相关离线回归、原始样本/13 个 demo 复测及 SunSmart generic iOS Debug 构建通过。Site 15 的最终列表可见性和 Space 1 进入操作尚待真机验收。本文前半部分保留修复前的诊断证据。

## 结论与证据边界

已复现一个足以阻断 Site 导入的兼容问题：服务器 Site 15 响应中的 `latitude`、`longitude` 是空字符串 `""`，当前生产解析器将其判为非法，导致整个 Site 更新提前失败。单 Space 加入入口又只依据服务器加入成功提示“成功”，没有等待 Site 导入落库，因此可以出现“加入成功，但 Site 列表没有项目”。

这是本次现场的高置信解释，但尚未逐字段闭合：editor 加入后的 `/sitespace/get/sitelist` 完整响应没有保留在日志中，不能直接证明其中包含 Site 15，或其坐标与提供的 owner `/get/siteprops` 响应完全相同。若列表根本没有返回 Site 15，还存在服务端列表可见性问题，现有证据不能排除这一分支。

初始分析已确认服务器加入成功；未确认 editor 本地 Site/Space 最终数据库状态。初始分析阶段未修改业务代码、SDK、数据库定义或序列化逻辑，未构建 App、未操作真机、未调用服务器接口。后续授权实施结果见文末。

## 环境与输入

- 分支：`feat/daylight-saving-261024`；HEAD：`59be4df7ffe3427af1fad1a45a6514e2813eb1ed`。
- 工作树已有 Cloud 同步、Database、SiteData、Sites/Site 控制器、测试和文档的未提交改动；本分析保留这些改动。空坐标解析器及单 Space 成功提示逻辑不在本轮开始时的未提交差异中。
- 本地 SDK 映射：`.local-sdk/nordic-sig-mesh-sdk` → `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`；本次解析器复现只依赖 Foundation，无 SDK 调用。
- [Owner 导出 JSON](</Users/maginawin/Downloads/Site_Site 15_20261106_111417_909+0800.json>)。
- [Editor 导入日志](</Users/maginawin/Desktop/import sharing site 15 logs.txt>)。
- [服务器 Site 属性响应](</Users/maginawin/Desktop/server site 15 data.txt>)。
- Site UUID：`DE33126C-B08C-4ADD-9132-3F33CC73ED24`；Space UUID：`A6DC053D-0334-4448-827C-5BA6B479106A`。

本文不保存密码、分享 token 或 Mesh 密钥。

## 现场证据

| 环节 | 直接证据 | 能证明的范围 |
| --- | --- | --- |
| 扫码信息 | 日志 133–153 行：`share/info` 返回 `type=single`，指向 Site 15 / Space 1 | 实际走单 Space 分享入口，并非 Site 所有权转让 |
| 提交权限 | 日志 601–610 行：`share/receive` 请求 `roleName=editor` | 用户申请的是 editor 权限 |
| 加入回执 | 日志 612–619 行：HTTP 200、业务码 200、`success` | 服务器接受了加入操作，不支持“密码错误”的解释 |
| 服务器成员关系 | 提供的 siteprops 中，Space 1 的 `editor.userId` 与日志请求账号相同 | 服务端已建立该 editor 关系；该 siteprops 的根 `role=owner`，并非 editor 的读取样本 |
| 加入后刷新 | 日志 624–645 行：再次请求 `get/sitelist`，HTTP 200，解码完成 | 刷新请求确实发出；不是完全漏发刷新通知 |
| 列表正文缺失 | 日志 642 行：`body=<body omitted: 33039 bytes>` | 无法直接核对列表中 Site 15 是否存在、具体字段是什么 |
| 导入阶段 | 加入前、加入后各有 17 个 Site 的 `phase=begin`，均不包含 Site 15 | Site 15 没有进入阶段计时点；不能单凭此断言服务器没返回，因为早期校验失败也不记阶段日志 |

`share/receive` 的正文同样被截断；可见前缀包含 `data.site`，但不足以验证完整字段。单 Space 加入代码没有使用该响应内容导入 Site。

## 阻断链路

### 1. 服务器空坐标与 App 校验不兼容

[SitePropsEditPolicy.swift](../SunSmart/Main/Site/Model/SitePropsEditPolicy.swift) 的 `SiteStandardProperties.Patch.init`（103–119 行）接受坐标缺字段、`null`、合法数字及数字字符串。对字符串调用去空白后的 `Double(...)`；空串不能转换，因此抛出 `invalidField`。

提供的服务器 JSON 为 `latitude: ""`、`longitude: ""`，不是合法数字字符串，也不是 `null`。时区 `Africa/Addis_Ababa` 不参与该失败分支。

[ImportData.swift](../SunSmart/Common/Data/ImportData.swift) 第 595 行通过 `try?` 解析全部标准属性；解析失败立即 `return false`。阶段计时器在第 626 行才创建，Site 保存位于第 1389 行。因此，空坐标会使整个 Site 在计时和保存之前被拒绝，而不只是让坐标为空。

随后 `SiteData.import` 第 562–563 行返回 `nil`。[SitesViewController.swift](../SunSmart/Main/Site/Controller/SitesViewController.swift) 第 335–338 行仅收集非空结果，未向用户展示该 Site 的失败原因；第 382–383 行保存结果并重载列表。列表数据源来自本地 `SiteData.loadAll()`，新 Site 若未落库就没有可展示的记录。这里没有按设备数量隐藏 Site 的规则，Space 1 的 `nodes=[]` 本身不解释该现象。

### 2. “成功”提示没有验证 Site 导入完成

[SharePermissionSelectionController.swift](../SunSmart/Main/Share/Controller/SharePermissionSelectionController.swift) 的单 Space 分支：

1. 第 659 行由扫码摘要构建临时 Space，初始 `meshNetworkId` 为空；这里并未创建完整 Site。
2. 第 142 行使用 `case .success(_)`，忽略加入接口返回内容。
3. 第 167–179 行授权加入并尝试保存 Space 元数据；`space.save()` 的布尔结果也未检查。
4. 第 181 行直接显示成功。
5. 第 182–184 行延迟 1.5 秒发列表刷新通知，再由列表接口导入 Site。

所以该提示证明的是“服务器加入成功，并执行了本地元数据保存尝试”，不是“Site 和 Space 已完整导入、持久化并可展示”。本次没有证据证明 `space.save()` 失败，但该结果被忽略是确定存在的错误反馈缺口。

批量 Space 加入也将加入结果处理与后续列表刷新分开，应纳入同类入口核对；Site 所有权接收有独立流程，不能混作本次路径。

## 生产解析器复现

在临时目录编译当前 `SitePropsEditPolicy.swift` 及既有依赖，使用 Foundation `JSONSerialization` 直接读取用户提供的原始 JSON，再调用生产 `SiteStandardProperties.Patch`。不修改生产代码，不复制真实密钥到夹具，不使用自写解析器代替生产实现。

| 输入 | 实际结果 |
| --- | --- |
| 原始服务器 Site 15 `data` | `REJECT invalidField("latitude")` |
| 仅将服务器纬度改为 `null` | `REJECT invalidField("longitude")` |
| 将服务器经纬度都改为 `null` | 接受，经纬度均为 `nil` |
| 仅移除服务器两个坐标字段 | 接受；缺字段语义仍为保留已有值，复现以空初值运行 |
| 原始 owner 导出的 `site` | 接受，纬度 `22.634437`、经度 `113.931436` |
| 空串或纯空白纬度 | 拒绝 |
| 纬度字符串 `"0"` | 接受为 0，不应误作空值 |
| 非数字字符串或超出纬度范围 | 拒绝 |

编译和复现进程均以 0 退出。测试边界是实际 JSON 解码与生产属性解析器；没有执行完整 Mesh 导入、SQLite 持久化、网络请求或 UIKit 展示，不能据此声称现场端到端恢复。

现有 [SitePropsAPIResponseParserTests.swift](../Tests/Site/SitePropsAPIResponseParserTests.swift) 第 93–98 行明确将空串和纯空白列入拒绝样例。因此这是现有输入约定与现场返回的差异，不能以既有测试通过排除该问题。

## 关联发现与后续边界

Owner 导出含有效坐标、城市等资料，服务器对应字段却为空；两者 `updateTimestamp` 均为 `1793933719`。Owner 原始本地行中 `lastUploadCloudTimestamp` 也是该值，`pendingSitePropsMask=0`、`syncCloudError=null`。这证明本地“已同步”记录与提供的远端属性内容不一致，但缺少对应上传请求和回执，不能推断字段在哪次上传、保存或覆盖中变空，也不能归因为 editor 扫码造成。

最短补证是获取本次 editor 账号 `get/sitelist` 中 Site 15 的单条对象，保留 `uuid/siteName/role/latitude/longitude`，并仅记录主网络密钥是否存在及格式校验结果，不输出密钥。若该对象存在且两个坐标为空串，本次列表缺失的现场链路即可闭合；若对象不存在，则由服务端团队核对 editor 成员关系到 Site 列表的可见性契约。

后续 App 修复需要同时处理已确认的空坐标兼容问题与成功提示时机：仅在实际导入、保存及重载确认后报告本地导入完成；失败应保留服务器已加入事实，允许重新读取恢复，不能反复把加入操作当作导入重试。

分析阶段没有数据结构变更。当时只考虑空字符串兼容；后续用户明确要求将坐标解析失败统一置空，具体范围见下节。Mesh 身份和权限校验继续保持原有规则。

服务器空值输出是否统一为 `null`、以及 Owner 属性为何与服务器不一致，均由服务端团队结合完整请求和存储证据核对；本轮不要求或实施服务器修改。恢复验收至少覆盖首次导入、已有 Site 再加入、空坐标/合法坐标、导入或保存失败后的重试、退出重进与重启，最终确认 Site 15 可见并能进入 Space 1。

## 2026-11-06 用户指定优化：坐标解析失败置空（已确认实施）

用户要求：`latitude`、`longitude` 解析失败不再导致整体失败，使用默认空值。当前 App 完整 Site 导出通过 `standardProperties.jsonObject` 生成这两个字段；Site props 更新也复用该逻辑。有值为数字字符串，无值为 JSON `null`。App 内存和数据库使用可空数值，而不是字符串。

已保存可解析的 [变更前后 demo JSON](261106_1122_site15_coordinate_fallback_demo.json)，包含 13 个坐标片段案例；它不代表完整 Site 导入载荷，不含真实凭据或密钥。

### 变更清单

| 项目 | 当前行为 | 拟改行为 |
| --- | --- | --- |
| 合法数字/数字字符串 | 有限且在范围内时转为 `Double` | 保持；0 和正负边界值仍有效 |
| 空串、纯空白、非数字字符串 | 坐标校验失败，拒绝整个 Site | 相应坐标设为 `nil`，继续其他字段处理 |
| 布尔、数组、对象等错误类型 | 拒绝整个 Site | 相应坐标设为 `nil` |
| 非有限数值、溢出或越界 | 拒绝整个 Site | 相应坐标设为 `nil`；不保存非法数值 |
| 一个坐标无效、另一个合法 | 整体拒绝 | 按字段独立处理，保留合法值 |
| 显式 `null` | 应用时清空对应坐标 | 保持 |
| 列表/部分响应缺字段 | 保留本地对应值 | 保持 |
| 完整详情缺字段 | 既有完整快照规范化为 `null` | 保持 |
| 数据库表、字段类型、约束、关系 | 可空 `Double` | 无变化，无迁移 |
| 导出/上传 Key、层级、类型 | 有效值为 string，空值为 null | 无变化；本次新容错得到的空值继续导出为 null |

### 影响与实施边界

- 修改共享解析入口 `SiteStandardProperties.Patch.init`，影响 Site 列表/详情导入以及 Site props 读取、更新回执解析。它们均使用相同语义，避免仅扫码入口绕过校验。
- 涉及模型与读写入口：`SiteStandardProperties` / `SiteData.standardProperties`；`ImportData.swift` 的 Site 更新、`SitePropsAPIClient` 的 retrieve/update response、`Database.swift` 的标准属性保存/读取、`ExportData.swift` 的 Site 导出。预计生产改动只需共享属性解析器，保存及导出复用既有机制。
- 接受“字段存在但无效”代表空值：当既有版本和冲突规则允许应用该响应时，会清空对应的旧坐标。缺字段不因此被当作解析失败，正常数值也不会因为另一坐标无效而被清空。
- 不主动重写已有数据库行；旧数据在后续正常读取云端快照时按新规则应用。导入/导出仍保持 string-or-null 的外部格式；无 SDK 或服务器结构变更，无新增持久状态。
- 其他字段的校验、Site 版本冲突处理、Mesh 身份和权限校验保持现有行为。本次授权范围是坐标容错，先前发现的成功提示时机缺口另列，不合并实施。
- 共享代码影响各品牌，无品牌分支或资源变化。实施后验证实际 JSON 解码、两坐标独立回退、空值/缺字段、保存重开与导出，再构建一次代表 SunSmart 的 generic iOS Debug。真机由用户刷新已加入的 Site 列表并进入 Space 1 验收。

### 确认状态

用户已在展示变更清单和 demo 后明确回复“按此方案实施”。后续实现沿用该范围，无新增字段、数据库迁移或上传格式变化。按用户最新规则，本轮未启用 Superpowers 或子代理。

## 实施结果与验证

生产代码仅修改 [SitePropsEditPolicy.swift](../SunSmart/Main/Site/Model/SitePropsEditPolicy.swift) 的共享坐标解析器：字段存在时保留“已提供”标记，无效类型/字符串或非有限/越界值保留默认 `nil` 并继续解析另一字段。缺字段、显式 `null`、合法数字与数字字符串沿用原有语义；其他字段仍可因无效数据拒绝导入。

扩展三个既有测试文件，保留其中已有的其他任务改动：

- [SitePropsAPIResponseParserTests.swift](../Tests/Site/SitePropsAPIResponseParserTests.swift)：实际 JSON 解码中的空串、布尔、数组、对象、越界、非数字，以及直接内存非有限值；独立清空旧坐标，保留合法另一坐标和其他资料；0/边界值保持数值；输出 string/null；无效 `cityId` 仍被拒绝。
- [SiteStandardPropsIntegrationTests.swift](../Tests/Site/SiteStandardPropsIntegrationTests.swift)：实际 props 解析、协调器合并及保存调用接受无效坐标；原来的“其他字段无效时拒绝”用例改用无效城市字段，保留原有失败/迟到/冲突断言。
- [SiteStandardPropsPersistenceTests.swift](../Tests/Site/SiteStandardPropsPersistenceTests.swift)：实际 JSON → 生产 Site 属性导入片段 → SQLite 保存/重开 → 列表读取 → string/null 导出；增加无效坐标回退在保存失败后的回滚与重试。之前已有的 Site Add 回执夹具改动保持不变。

| 验证 | 结果与边界 |
| --- | --- |
| `bash scripts/check_site_props.sh` | 通过；包括 props policy/parser/integration 及入口时区 policy/coordinator。抽取导入夹具存在未使用 `uuid` 的编译告警 |
| `python3 scripts/check_site_hdb_persistence.py /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev` | 通过；真实 SQLite 保存/重开、无效坐标回退、失败重试、既有 Site/HDB 回归均通过；抽取夹具同样有未使用 `uuid` 告警 |
| 最终边界值断言加强后的 parser 单独编译执行 | 通过，生产代码未再次变化 |
| 用户提供的服务器 Site 15 JSON | 直接 JSON 解码后调用生产解析器，通过；两个坐标均为 `nil`，再序列化均为 JSON `null` |
| 用户提供的 owner 导出 JSON | 通过；两个合法数字字符串仍正确还原数值 |
| 已确认的 13 个 demo | 全部与生产解析后的导出结果相符；含部分响应与完整详情缺字段的区别 |
| SunSmart Debug generic iOS | `xcodebuild` 退出 0，生成 App；Xcode 构建清单记录 0 errors、119 warnings，包含依赖及弃用 API 告警 |
| `git diff --check` | 通过 |

构建入口为 `SunSmartLocal.xcworkspace`，scheme 为 `SunSmart`，使用 `-configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`。本轮使用隔离目录 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-daylight-saving-261024-coordinate-fallback`，无 clean、无共享缓存清理。

构建终端曾输出 CryptoSwift 的 `failed with exit code 0` 诊断文本；进一步核对原生 `Logs/Build/LogStoreManifest.plist`，本次构建记录确认为 0 个错误，且 App 可执行文件与 Info.plist 均为本次生成。因此按成功但有告警记录，未通过重复构建掩盖诊断。SDK 来源仍为 `one-dev`，HEAD 为 `2809c540be3b965a6a847ee4586ac46faf2ca2b5`，工作树干净且本轮未修改 SDK。

共享解析器在所有相关品牌 target 中已有归属，本次没有资源、依赖或编译条件变化，使用 SunSmart 代表构建；未重复其他品牌或 Release。

未运行真实 HTTP/扫码/UI/Mesh 验收。持久化夹具执行真实 SQLite 与生产属性解析/保存逻辑，但 Mesh/Space 初始化和网络请求是边界；生产原始 JSON 复测证明解析已修复，不替代完整现场导入验收。单 Space 加入提前显示成功的问题本次未修改，原始日志中 editor sitelist 正文缺失的证据限制也仍然存在。

最短人工验收：更新 editor App 后，在 All Sites 下拉刷新；服务器已记录加入关系，可先刷新而不重复扫码。预期 Site 15 出现，进入后可见 Space 1；退出重进或重启仍可见，未提供合法坐标时坐标保持空值。若仍不可见，补充 editor 当前 sitelist 中该 Site 的脱敏字段，确认服务端是否返回该项目。

未提交、推送或同步其他工作树；本任务之外的未提交改动均保留。
