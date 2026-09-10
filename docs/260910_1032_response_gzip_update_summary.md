# 已验证接口的 gzip 响应协商更新

## 改动

用户确认候选接口均支持 gzip 响应后，在 `SunSmart/Common/Network/NetowrkReqeustApi.swift` 的共享 headers 分支加入显式 `Accept-Encoding: gzip`。

新增覆盖 10 个路径、11 个 API case：

| 接口 | API case |
| --- | --- |
| `/sitespace/get/sitelist` | sites |
| `/sitespace/share/receive` | receiveSite、joinSpace |
| `/sitespace/ota/configfile` | devicesConfig |
| `/sitespace/site/batchshare/list` | batchShareList |
| `/sitespace/share/info` | shareInfo |
| `/sitespace/sapce/gateway/reference` | gatewayAssociationSpaceList |
| `/sitespace/ota/history` | firmwareVersionList |
| `/sitespace/space/singleshare` | spaceMembers |
| `/sitespace/get/activeuser` | spaceActiveMembers |
| `/sitespace/site/gateways` | gatewayList（分析文档中的备用接口，目前未发现业务调用点） |

保留原有 siteInfo、spaceInfo、siteUpload、spaceUpload，共 15 个 API case 显式协商 gzip 响应。复用现有 JSON 编码、URLSession/Alamofire 响应解码以及传输指标，不新增手动 gunzip。

请求体继续保持普通 JSON；devicesConfig 继续无正文。`HTTPBodyEncoding.prepare` 清除请求 Content-Encoding 的逻辑保持不变，未启用 gzip 上传。品牌头、身份、资源、本地化、target 配置、SDK 和依赖版本均未修改。

## 验证

- 临时源码检查通过：显式 gzip 分支准确覆盖 15 个 case，没有请求 Content-Encoding，task 保留 JSONEncoding/default 与无正文分支。此项是静态检查，不是线上请求抓包。
- `check_site_entry_performance.py` 通过：直接运行生产请求准备逻辑，验证大小 JSON、UTF-8、正文不变、请求 Content-Encoding 清除、响应 Accept-Encoding 保留、重复准备；同时通过脚本已有的 SQLite/地址语义回归。
- `SitePropsAPIContractTests` 通过：使用 swiftc 的 parse-as-library 模式编译后运行，Edit Site retrieve/update 契约保持。首次直接用 swift 解释执行因 @main 模式不匹配失败，改为正确编译方式后通过。
- 编码回归使用当前构建解析的 NordicSigMeshSDK release `a6246b1`，路径位于本工作树对应的 DerivedData `SunSmart-erjsxwlkutpcaeaobcajbiggnwbm`；未修改 SDK。

五品牌 generic iPhoneOS Debug 构建全部 **BUILD SUCCEEDED**：SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux。均直接执行 xcodebuild、关闭签名，不使用 Simulator。构建仍有既有工程警告（如 AppIntents 元数据提取跳过），未扩大范围处理。

`git diff --check` 通过。生产代码仅修改上述 headers 分支，未新增测试文件；复用现有回归及临时静态检查验证此次小范围配置改动。

## 验收边界

服务器支持情况来自用户本轮确认。本轮未发送生产业务请求，也未操作真机；没有测得实际压缩比或页面提速数值。Alamofire 默认配置原本就包含 gzip，因此本次显式设置不意味着所有接口都会获得新的压缩收益。

后续在设备上走相关查询、分享接收和导入流程，检查 `[HTTP][Metrics]` 的 encoding、receivedBytes、decodedBytes 及业务完整性，即可验证 App 端实际效果。普通 identity 响应继续按现有链路解析。

方案背景及参数见 [分析计划](260910_1020_response_gzip_analysis_plan.md)。未提交 Git。
