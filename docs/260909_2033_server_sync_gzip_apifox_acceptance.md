# 服务端同步接口修复清单与 Apifox 验收

日期：2026-09-09。依据：用户故障日志、当前 App 请求实现、Apifox 官方帮助。本文提供服务端实施与测试方法，不代表已部署或已通过真实服务器测试。

## 1. 哪些接口需要修复

故障日志的 base URL 为 `https://www.mericher.com/srv2`。下表路径均拼接在该 base URL 后，方法全部为 **POST**，包括名称中含 `get` 的查询接口。

| 接口 | 当前证据 | 服务端工作 |
| --- | --- | --- |
| `/sitespace/sync/siteprops` | 实际 gzip 上传返回 400 `parse_error`，UTF-8 解码遇到 `0x8B` | **确定需要修复请求解压链路**。同时覆盖 Site-only、Site 携带 Spaces、同一路径的首次 Site 创建 |
| `/sitespace/sync/spaceprops` | 兴东 Space 两次实际 gzip 上传均返回相同 400 | **确定需要修复请求解压链路**。同时验证完整 Space 配置持久化及后续可读 |
| `/sitespace/get/siteprops` | HTTP 200，gzip 响应已被 App 解码；其中另一个 Space 存在 invalidRemoteTopology | 不应判定为请求 gzip 故障。用于上传后回读；另立数据完整性排查项 |
| `/sitespace/get/spaceprops` | HTTP 200，但回读旧版本，与未成功上传相符 | 不应仅因 mismatch 判定查询接口有 bug。上传修复后，若仍返回旧版本，再检查读缓存、异步 worker、读写库及版本选择 |
| `/sitespace/space/singleshare` | 分享流程尚被前置同步挡住，没有该接口失败证据 | 作为联动回归，不列入已确认故障接口 |

`siteAdd` 与 `siteUpload` 在 App 中使用同一个 `/sitespace/sync/siteprops` 路径，但请求 envelope 略有不同。共享解析修复须覆盖二者，不能只覆盖某个 handler 分支。

App 还配置了亚太 `https://sunsmart-ap.mericher.com/srv2`、北美 `https://sunsmart-us.mericher.com/srv2`、欧洲 `https://sunsmart-eu.mericher.com/srv2`。本次只有 `www.mericher.com` 的故障证据；其他地区需要分别验收，不能直接宣称有相同问题或已经修复。

## 2. 服务端修复要求

1. JSON parser 前统一处理请求 Content-Encoding：无编码/identity 按 UTF-8 JSON 解析；gzip 则先完整解压并校验压缩流，再解析 JSON。未知编码返回明确的 415，损坏 gzip 或解压后无效 JSON 返回明确的 400，不能返回 500 或假成功。
2. 如果不支持 gzip，应明确拒绝编码，不能让压缩字节进入 UTF-8 parser；不过“改为返回 415”只代表错误处理改善，**不算完成 gzip 支持验收**。
3. `400 + code="parse_error"` 必须保证发生在业务写入前，不更新版本、节点、Group 或权限数据。业务校验/冲突使用不同业务码。App 已利用此语义结束对应的未接受提交回执。
4. 对压缩前后大小分别设置边界，并明确可支持的 500 节点请求大小。解压必须有大小限制，并完整验证尾部/校验和后再开始业务写入，避免流式解析提前保存部分配置。
5. 统一代理、中间件、业务 parser 的职责，避免未解压、重复解压、转发时 Header/Body 不一致。响应 gzip 与请求 gzip 是两件事，开启响应压缩不足以修复本问题。
6. 核实发布中的旧 App 是否曾发送“Content-Encoding=gzip，但 Body 是普通 JSON”。若确有存量客户端，在入口对这类可识别普通 JSON 做有限兼容并记录兼容命中；真实损坏 gzip 不允许降级解释成 JSON。不能为了兼容吞掉任意解压异常。
7. 对同一请求记录 requestId、服务实例、编码、压缩/解压字节数、解析结果、目标版本及写入结果；不要记录密钥、密码或完整 Mesh 配置。用这些记录把 Apifox 的请求与真实持久化关联起来。

## 3. Apifox 准备

使用测试账号及独立测试 Site/Space，先保存基线。全量上传不能拿空数组或随意编造的最小对象替代真实配置，否则可能测到业务校验失败或覆盖数据。

在 Apifox 新建测试环境：baseUrl、测试 userId、siteId、spaceId 及项目现有鉴权变量。沿用团队已有鉴权设置，不从故障日志复制生产身份。各地区建独立环境。

根据 App 构造器准备**完整请求体**：

| 用途 | 顶层字段 | 关键注意 |
| --- | --- | --- |
| Site 同步 | `site`、`user` | `user` 中为现有用户信息；`site` 为完整 Site 导出对象；`site.spaces=[]` 表示本次 Site-only 提交，需验证它不会删除已有 Spaces |
| 首次 Site 创建 | 上述字段，另有 `devicesInSetle` | 按 App 实际创建请求测试，不能用已有 Site 冒充创建 |
| Space 同步 | `siteId`、`spaceId`、`spaces`、`userId` | `spaces` 是含完整 Space 对象的数组，即使只传一个 Space；不要改成 `space` |
| Site 查询 | `siteId`、`userId` | JSON 请求 |
| Space 查询 | `siteId`、`spaceId`、`passwd`、`userId` | 使用测试账号当前有效权限密码；不能把日志中的 redacted 当值 |

获取样本优先使用测试 App 的实际上传 envelope 或团队现有成功用例。`get` 响应外层的 `code/data` 不是上传 envelope，普通导出 Space 也需要按上表封装。样本需保留 nodes、groups、profiles、scenes、schedules 及其他业务字段。

### 3.1 生成真实 gzip 文件

仓库提供本地工具 `scripts/prepare_apifox_sync_fixture.py`。它不访问服务器、不改变输入内容，生成普通 JSON、同内容 gzip、截断 gzip 和“有效 gzip 内含无效 JSON”四种文件，并输出字节数、SHA-256 及压缩往返验证结果。

从仓库根目录运行，例如：

`python3 scripts/prepare_apifox_sync_fixture.py /tmp/apifox-space-request-B.json /tmp/apifox-space-B`

输入文件必须是**已替换变量后的完整测试请求 JSON**；输出目录必须尚不存在。真实请求样本保存在仓库外，不加入 Git。普通请求可使用 Apifox 变量，但已压缩的 binary 文件不会替换其中的 `{{变量}}`；更换账号、目标 ID、版本或名称后，重新生成文件。

生成文件用途：

| 文件 | 内容 | 用途 |
| --- | --- | --- |
| `identity.json` | 输入原始字节，不重新序列化 | 普通 JSON 对照、旧 App Header 不匹配兼容测试 |
| `request.json.gz` | 与 identity.json 完全相同内容的 gzip，起始字节 `1F 8B` | 真正 gzip 上传 |
| `truncated.json.gz` | 缺少 gzip 尾部 | 验证截断/校验失败不会部分写入 |
| `invalid-json.json.gz` | 压缩流有效，但解压后 JSON 不完整 | 验证 JSON parser 错误契约 |
| `manifest.json` | 路径、字节数、文件散列与 round-trip 结果 | 留存测试证据，不包含请求原文 |

工具只检查基础 envelope 和 gzip 字节正确性，不能替代服务端业务校验。

### 3.2 在 Apifox 发送

1. 新建 POST 请求，URL 使用 `{{baseUrl}}/sitespace/sync/spaceprops` 或 Site 同步路径。
2. 普通 JSON 用例：Body 选 JSON，粘贴完整已解析对象；或者 Body 选 **binary**，选择 `identity.json`，这样可保留文件原始字节。Headers 设置 `Content-Type: application/json`、`Accept-Encoding: gzip`，移除 `Content-Encoding`。
3. gzip 用例：Body 选 **binary**，选择 `request.json.gz`；Headers 设置 `Content-Type: application/json`、`Content-Encoding: gzip`、`Accept-Encoding: gzip`。不要使用 form-data，不要把 `.gz` 作为文件字段上传，不要发送 Base64 文本，不要粘贴 JSON 后仅增加 gzip Header。
4. 不手填 Content-Length，让客户端按实际文件字节计算；检查并覆盖 binary 可能带来的 `application/octet-stream` 默认值，避免重复 Content-Type。检查公共 Headers/前置操作没有再次压缩或覆盖请求 Body。
5. 在发送详情/控制台核对实际 URL、Headers 和请求长度；和 manifest、服务端入口收到的字节数/编码日志配对。body 应为整个 gzip 文件，而非 multipart 包装。

Apifox 的 binary 请求体支持选择二进制文件，参见[请求参数与请求体](https://docs.apifox.com/5220200m0)。断言可在后置操作中添加，按 JSONPath 检查正文，参见[断言](https://docs.apifox.com/assertions)。

## 4. 测试用例与通过标准

每个同步接口都执行下表；Site 另覆盖 Site-only、带 Space、首次创建；Space 覆盖小样本与真实 500 节点样本。每个成功测试应使用**之前未写入的新版本和可识别名称标记**，避免只是读到旧数据也被当作成功。

| 编号 | Body / Header | 预期 |
| --- | --- | --- |
| A | 普通 JSON，无 Content-Encoding | HTTP 200、业务成功、能回读本次新版本 |
| B | 真实 gzip，Content-Encoding=gzip | HTTP 200、业务成功、能回读本次新版本；不能再出现 UTF-8 0x8B 错误 |
| C | 同 A/B，UTF-8 中英文名称、完整 500 节点数据 | 无乱码、无 413/超时、节点身份/Group/Profile 保持一致；记录字节数及耗时 |
| D | 普通 JSON，但 Content-Encoding=gzip | 若确认有历史客户端，则须兼容且回读正确；若没有此兼容契约，可明确 4xx 拒绝，但不得污染数据 |
| E | 截断 gzip，Content-Encoding=gzip | HTTP 400、明确解析/解压错误、无任何业务写入，不允许部分保存 |
| F | 有效 gzip，解压后不是有效 JSON | HTTP 400、`$.code = parse_error`、无业务写入 |
| G | 普通 JSON，Content-Encoding=x-unsupported-test | HTTP 415、明确不支持编码、无业务写入 |
| H | 完整配置触及/超过约定解压大小上限 | 上限以内成功，超限明确拒绝（建议 413）、无 OOM/500/部分写入；在隔离测试环境执行 |
| I | 成功上传之后，通过 Site 与 Space 两种查询读取 | 目标 Space 的 UUID、版本、业务配置一致，不因查询入口或服务实例不同而回退 |

普通 JSON A 通过只说明 App 兼容修复可以工作；**B 和 C 的真实 gzip 请求通过才证明服务端请求解压已修复**。E/F/G 的错误处理通过不代替成功用例。

### 4.1 成功上传的回读方法

以 Space 为例：

1. POST `get/spaceprops` 读取测试基线 A，保存完整 `data`、当前版本和节点/Group 身份集合。
2. 基于合法完整配置准备 B，只修改测试名称为 `Gzip Acceptance B` 等标记，并按接口现有版本规则设置比已保存版本更新的 `updateTimestamp`；不要设遥远未来的时间。保留节点/Group/Profile 全量结构。
3. 为 B 生成 gzip，**首先通过 gzip 上传 B**，此前不要把 B 的普通 JSON 对照上传到服务器。
4. 上传响应在 Apifox 添加断言：HTTP 状态 200、业务 `$.code=200`（若具体接口已有 `isSuccess=true` 契约则按该契约）、错误码不为 parse_error。
5. POST `get/spaceprops`，添加断言：`$.data.uuid` 等于目标 Space、`$.data.updateTimestamp` 等于本次提交版本、`$.data.spaceName` 等于 B 标记。若接口有明确的服务端版本生成规则，按已确认的返回版本契约断言，不能静默接受旧版本。
6. 核对 `$.data.nodes` 数量及完整 UUID 集合；核对每个节点的 unicastAddress、Group 归属及提交配置字段。500 个数量相等仍可能是不同设备。
7. 按 `groups[].address` 对齐 Group，核对完整 profile、scene 及 path/zone 引用。不要只按数组下标比，也不能仅比请求/响应原始文件 SHA-256：字段顺序、服务端生成的权限/资源元数据可能不同。
8. 再 POST `get/siteprops`，从 `data.spaces` 按 UUID 找到同一 Space，检查同一版本与配置。另一个授权客户端/App 重读也应一致。
9. 如果服务端明确采用最终一致性，记录每次回读的 requestId、实例、版本和时间，在双方约定窗口内有限重试；超过窗口即失败。不能只增加重试次数掩盖一直返回旧配置。

Site-only 的做法相同，以 `site.siteName` 和 `site.updateTimestamp` 为提交标记，以查询 `data.siteName/updateTimestamp` 核对。额外比较上传前后 Space UUID 集合及各 Space 版本/配置，确认 `site.spaces=[]` 没有删除或覆盖它们。带 Space 的 Site 同步则同时验收 Site 与每个 Space。首次 Site 创建需核对地址资源等既有响应契约。

后置操作可用“提取变量”保存基线/预期值，然后用 JSONPath 断言；复杂集合比较可使用团队脚本。官方提供 `pm.response.json()`、`pm.test()`、`pm.expect()` 等 API，参见 [pm 脚本 API](https://docs.apifox.com/pm-%E8%84%9A%E6%9C%AC-api-5580997m0)。此处的“业务配置按身份比较”是本项目的验收要求，不是 Apifox 内置的自动一致性判断。

### 4.2 失败用例必须证明没有写入

先回读保存当前基线；为失败请求准备新的名称/版本后再生成坏压缩体。E/F/G/H 响应后重新查询 Site 和 Space，版本、名称、节点 UUID 集合与 Group/Profile 都应保持基线。服务端同时核对该 requestId 未进入提交阶段。

E 尤其要用包含新版本的完整 B JSON 压缩后截断尾部，才能检出“读到 JSON 就写库，尚未验证 gzip 尾部”的错误。仅发送两个随机坏字节测不到这种部分写入风险。

## 5. 单独的数据完整性排查

日志中 Space ID 前缀 `78F5111F` 的远端为 59 Nodes、本地为 60 Nodes，并出现多项 `sequence[...]` 修复项。服务端需分别取该 Space 的 Site 查询嵌套对象与 Space 单独查询结果，对比数据源、版本、节点 UUID/地址、Group/Path/Sequence 引用与既定跨 Space 归属规则。

确认是历史残留、导出投影差异、删除迁移遗漏，还是合法旧版本尚未更新后，再决定数据迁移/读写逻辑修复。不能仅凭 `hardErrors={}` 删除全部 sequence，也不能把另一个 Space 的异常归为兴东 gzip 400。该项验收独立于请求压缩。

## 6. 服务器修复完成的判定

- 两个 sync 接口都通过 identity 与真实 gzip 的新版本写入/回读；Site-only、Site 携带 Space、首次创建和 500 节点场景覆盖完整。
- 负向用例返回约定 4xx，且版本与全量业务状态未变化。
- Apifox 回读、服务端写入记录与另一客户端显示相互吻合；各实际部署地区及服务实例分别有证据。
- 真机进入 Site → Space 更多菜单 → Share → 同步完成 → 再次 Share，能够进入分享页面，接收方看到一致配置。

留存环境、服务版本/实例、测试时间、requestId、fixture manifest、HTTP/业务结果、上传/回读版本、节点身份及 Group 对比结论、耗时、负向用例前后差异。只有 App 构建通过或查询响应支持 gzip，不满足服务器验收标准。
