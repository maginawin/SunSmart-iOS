# Site / Space gzip 请求实测与 App 接入

日期：2026-09-10。工作树：`fix`。按用户要求，先以用户提供的测试文件验证真实服务器，再修改 App。

## 结论和启用范围

中国大陆 `https://www.mericher.com/srv2` 的两个同步接口均已通过真实 gzip 上传、业务成功和新版本回读验证。用户随后确认四个地区均已部署，App 已在四个地区的两个同步 POST 路径启用 gzip，覆盖 Site 创建、Site 同步及 Space 同步。

用户明确要求不再测试其他服务器，以中国大陆成功结果作为本次验收依据。App 不设置域名限制；没有向其他地区上传测试配置。其他地区部署状态来自用户确认，不宣称完成其他地区实测。

前置无业务身份探测见 [解析层实测与计划](260910_1110_sync_request_gzip_probe_and_plan.md)。本文补充该文当时缺少的成功用例与实施结果。

## 用户原始文件测试

原始文件位于用户 Downloads 目录，未修改、未加入仓库。完整回读包含测试配置及 Mesh 数据，仅保存在权限受限的 `/tmp/sunsmart-sync-gzip-260910/`，本文不记录身份或密钥。

| 接口 | 文件 | 解压后字节 | 原始 gzip 字节 | 减少比例 | 上传结果 | 上传耗时 |
| --- | --- | ---: | ---: | ---: | --- | ---: |
| /sitespace/sync/siteprops | aec-demo-test.json.gz | 862,354 | 23,472 | 97.3% | HTTP 200 / code=200 | 0.255 s |
| /sitespace/sync/spaceprops | spaceprops-body.json.gz | 32,998 | 3,209 | 90.3% | HTTP 200 / code=200 | 0.086 s |

上传时直接发送文件二进制字节，Content-Type 为 application/json，Content-Encoding 为 gzip。没有添加 Auth，使用测试 envelope 自带的用户信息。

Site 样本包含 devicesInSetle 和一个 Space，Space 有 38 个节点、4 个 Group、2 个 Schedule；目标 Site 已存在，因此只能认定覆盖创建格式的已有 Site 同步，不能称为全新 Site 创建验收。Space 样本含 1 个节点、2 个 Group、1 个 Switch。其顶层缺少当前 App 的 spaceId，但本次服务器接受了该样本；App 的现有 envelope 保持不变。

原文件版本已存在于服务器，首次上传前后回读完全一致，单凭上述 200 不能证明发生新写入，因此继续执行下面的新版本验证。

## 新版本写入、双入口回读与恢复

以原文件生成临时请求对象，不修改原文件。仅更新 Site/Space 的 updateTimestamp，并给名称追加临时标记 ` Gzip Test`。Site 请求同时更新其中 Space 的版本与标记。每个接口先提交标记版本，再使用更高版本恢复原名称，共四次真实 gzip 上传，均 HTTP 200 / code=200。

| 场景 | 紧凑 JSON 字节 | gzip 字节 | 上传耗时 | 回读结果 |
| --- | ---: | ---: | ---: | --- |
| Site + Space 标记版本 | 189,996 | 20,932 | 0.260 s | Site 和 Space 名称、版本匹配 |
| Site + Space 恢复原名称 | 189,976 | 20,845 | 0.237 s | 原名称已恢复，新版本匹配 |
| Space 标记版本 | 8,831 | 2,977 | 0.104 s | Site 嵌套对象与 Space 查询均匹配新名称、版本 |
| Space 恢复原名称 | 8,821 | 2,963 | 0.078 s | 原名称已恢复，新版本匹配 |

临时请求重新序列化为紧凑 JSON，故与原文件解压后的字节数不同；不能把原文件大量空白带来的压缩收益直接当作 App 的典型收益。临时 gzip 使用 level 1，并在本地验证压缩往返字节相等。

回读核对结果：

- Site 和 Space 两种查询均读到标记版本及恢复版本，没有把旧配置误判为本次成功。
- 节点 UUID 集合、节点数量、Group、Schedule、Scene、Switch 及 Space 样本的 spaceData 与提交配置一致；Group/Profile 嵌套对象按完整结构比较。
- 用户原始数据与回读存在服务器补充字段及 gatewayInfo 等既有差异；查询入口之间也存在 nodes[].props、userEvents、shareId 的投影差异。剔除这些已识别的查询投影差异后，同一 Space 的两种查询对象完全一致。
- 以同一查询入口比较上传前基线与最终回读，Site 测试仅 Site/嵌套 Space 的 updateTimestamp 改变，Space 测试仅目标 Space 的 updateTimestamp 改变，其他配置恢复为基线。版本不会倒退恢复为旧值。

证据文件：report.json、fresh-report.json、fresh-network-report.json 及前后回读，均在上述临时目录。fresh-report 中原始全对象比较的 false 不代表关键业务配置不一致，应结合本节已定位的投影字段解释。临时文件可能被系统清理，本文保存主要结论。

## App 改动

- `SunSmart/Common/Network/NetworkRequest.swift`：沿用现有后台编码队列，在 Moya 序列化后由 HTTPBodyEncoding.prepare 压缩最终正文。针对四个地区的两个同步路径、POST、非空正文启用，不设置大小阈值。
- 复用已有 Data+Gzip，使用 bestSpeed；压缩后设置 Content-Encoding: gzip，清除旧 Content-Length，由网络栈根据最终字节生成。重复处理已有 gzip 正文保持原字节。空正文不声明 gzip。
- 保留 Content-Type、Accept-Encoding 和现有 envelope；压缩错误沿现有请求失败路径返回，没有自动降级重发，没有扩大同步回执释放条件。
- `NetowrkReqeustApi.swift`：仅更新响应协商注释，说明它与请求压缩策略独立。
- `Tests/Group/SiteEntryPerformanceTests.swift`：更新真实 gzip 往返、UTF-8、大小请求、创建 envelope、长度头、重复准备、查询、四地区一致性、空正文和非 POST 边界回归。

未修改 SDK、依赖、UI、国际化或资源。开始业务代码编辑前，工作树已有用户的 project.pbxproj 改动，本次保留，未操作该文件。未提交 Git。

## 验证结果

- `check_site_entry_performance.py`：通过；使用当前 fix 工作树对应 DerivedData 中解析出的 SDK。首次误选另一工作树缓存导致提取旧 SDK 源片段失败，改用当前实际缓存后通过，未为适配错误缓存修改测试脚本或 SDK。
- `check_network_response_queue.py`：通过。
- `check_space_recovery_receipts.py`：通过，现有解析拒绝、未知结果及冲突保护保持。
- `git diff --check`：通过。
- 最终四地区启用版本的 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 五品牌 generic iPhoneOS Debug 构建全部通过。

构建直接使用 xcodebuild、SunSmart.xcworkspace、对应 scheme、Debug、iphoneos、generic/platform=iOS 和 CODE_SIGNING_ALLOWED=NO。没有使用 Simulator，也没有 shell 包装或日志重定向。解析的 NordicSigMeshSDK 仍为 release / a6246b1b0409824a3227a9c7cad8140219feb182。

构建仍输出工程既有的资源/编译条目及 AppIntents 等警告，本次未扩大范围处理。地区策略调整后重新运行编码回归，并对最终代码完成五品牌构建。

## 验证边界

本次成功实测覆盖用户提供的两个测试样本；未执行 500 节点压力测试、全新 Site 创建、Site-only 无 Space 上传、其他三个地区业务测试或真机完整同步/分享验收。原始请求最大约 862 KB，不能据此声明任意大请求均可接受。App 通用编码回归与构建不代替这些设备和服务端场景。
