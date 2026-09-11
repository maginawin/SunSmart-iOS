# 同步请求 gzip 实测与接入计划

日期：2026-09-10。工作树：`fix`。用户要求先模拟验证服务器支持，再开始修改 App。

后续进展：用户提供测试文件后已完成成功上传、新版本回读和 App 四地区接入，详见 [实测与实施结果](260910_1127_sync_request_gzip_implementation.md)。下文保留首次解析层探测时的结论与计划。

## 当前结论

中国大陆 `https://www.mericher.com/srv2` 的两个同步接口已通过请求解压层探测：真实 gzip 解压后进入 JSON parser，截断 gzip 被明确拒绝。尚未进行合法配置上传、持久化和回读验证，因此本轮不修改 App 代码，不将解析层结果表述为完整同步验收成功。

暂按仓库近期故障记录中的中国大陆域名开展无业务身份探测；已向用户询问最终测试地区及可写入的专用测试 Site/Space 或测试请求样本路径。其他三个地区未测试。

## 本轮实际测试

时间：2026-09-10 11:10:11（UTC+8）。使用 Python 标准库直接 POST 到真实服务器，无自动业务重试。无新增或使用 Auth 信息。

两个接口各发送三种请求，共六次。解压后的测试内容都是故意缺少字段值的无效 JSON，不包含 userId、Site/Space 标识或任何真实配置。请求 Content-Type 为 application/json；Accept-Encoding 为 identity，以单独观察请求压缩。

| 接口 | 请求体 | 请求字节数 | HTTP / 业务结果 | 耗时 |
| --- | --- | ---: | --- | ---: |
| /sitespace/sync/spaceprops | 无效 JSON，无 Content-Encoding | 13 | 400 / parse_error，Line 1 Column 14 (Char 13) | 0.074 s |
| /sitespace/sync/spaceprops | 同一内容的真实 gzip，Content-Encoding: gzip | 33 | 400 / parse_error，同一 JSON 解析位置 | 0.043 s |
| /sitespace/sync/spaceprops | 上述 gzip 截去末尾 8 字节 | 25 | 400 / code=400，Invalid gzip request body | 0.051 s |
| /sitespace/sync/siteprops | 无效 JSON，无 Content-Encoding | 13 | 400 / parse_error，Line 1 Column 14 (Char 13) | 0.056 s |
| /sitespace/sync/siteprops | 同一内容的真实 gzip，Content-Encoding: gzip | 33 | 400 / parse_error，同一 JSON 解析位置 | 0.124 s |
| /sitespace/sync/siteprops | 上述 gzip 截去末尾 8 字节 | 25 | 400 / code=400，Invalid gzip request body | 0.048 s |

无敏感内容的原始测试记录：`/tmp/sunsmart-gzip-parser-probe-260910.json`。临时文件可能被系统清理，关键结果已保存于本文。

证据说明：普通正文与 gzip 正文触发相同的解压后 JSON 解析位置，支持服务器已正确解压这一判断；结果已不同于昨天的 gzip 字节被直接当作 UTF-8 解析。截断流得到专门的 gzip 错误，证明本次样本受到压缩完整性检查。以上不证明合法业务对象被接受、大配置容量达标、数据库未部分写入或所有服务实例均已部署。

## 写代码前还需完成的成功验证

使用用户指定的测试环境和可写入专用数据，沿用现有身份，不在代码或文档中加入凭据。不得用真实用户 Space 的空 nodes/groups 数组进行试写。

1. 保存测试 Site/Space 的完整基线及版本；确认请求 envelope 与 App 一致。普通 JSON 使用版本 A，后续 gzip 使用不同的新版本 B，避免普通上传先写入 B 导致回读假阳性。
2. 对 Space 同步发送完整 gzip 请求，核对 HTTP 和业务成功，再通过 Space 与 Site 两种查询回读 B 的名称、版本、节点身份集合、Group/Profile、场景和日程配置。
3. 对 Site 路径分别覆盖 Site-only、Site 携带 Space、首次 Site 创建（额外 devicesInSetle 字段）。Site-only 检查既有 Space 集合未被清空；嵌套 Space 同时检查配置一致性。
4. 覆盖 UTF-8 中英文、较小完整请求和约 500 节点的完整合法样本，记录压缩前后字节与请求耗时。
5. 在专用测试数据上验证损坏 gzip 被拒绝后版本及配置不变。当前截断请求返回数字 code=400，与现有 parse_error 回执释放条件不同，应保留现有保守处理，不仅凭这一负向用例扩大回执清理范围。
6. 按实际上线地区分别记录结果；单个地区通过不直接推导其他地区能力。

详细 envelope 与回读字段沿用 [服务端同步接口修复清单与 Apifox 验收](260909_2033_server_sync_gzip_apifox_acceptance.md)。现有 `scripts/prepare_apifox_sync_fixture.py` 可在本地生成测试文件，但自身不证明服务器支持。

## 验证通过后的最小接入方案

- 修改 `SunSmart/Common/Network/NetworkRequest.swift` 中的 `HTTPBodyEncoding.prepare`，在 Moya 完成 JSON 序列化后压缩最终正文；保持现有后台 encodingQueue 和错误返回路径。
- 仅对两个已确认路径的 POST JSON 正文启用真实 gzip，覆盖 `.spaceUpload`、`.siteUpload`、`.siteAdd`。按本次“换成 gzip”的要求，对这些请求的小/大非空正文均启用，不沿用旧 1 KB 阈值；部署地区范围以实测结果和用户环境信息确定。
- 复用已有 `SunSmart/Thirdparty/Gzip/Data+Gzip.swift`，无需新依赖或 SDK 修改。压缩成功后设置 Content-Encoding: gzip，保留 application/json 与现有响应协商，清除旧 Content-Length 交由网络栈重算。
- 保证重复准备不会二次压缩，Header 与实际字节一致；压缩失败通过现有请求失败路径返回，不静默改用普通正文重发同步请求。
- 更新 `NetowrkReqeustApi.headers` 中“请求体保持未压缩”的过时注释。其他接口、业务 JSON envelope、导入导出格式和提交回执策略保持现有语义。
- 更新现有 `Tests/Group/SiteEntryPerformanceTests.swift`：验证两个上传路径大小正文 gzip 往返无损、UTF-8、长度头清理、重复准备、查询不压缩及 Accept-Encoding 保留，并覆盖首次创建形态。
- 运行现有相关编码/网络/回执回归；直接用 xcodebuild 验证 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 五个共享品牌的 generic iPhoneOS Debug 构建，不使用 Simulator。无需修改 UI 或本地化资源。
- 真机完成 Site 创建、Space 同步与分享前同步，并核对实际上传编码及服务器回读；构建通过不能替代这一步。

## 本轮改动与待补条件

仅新增本文。未修改 App、SDK、测试代码或依赖，未运行构建，未提交 Git。已完成六次解析层探测；合法上传与回读缺少指定的专用测试数据，接入实施保持待验证状态。
