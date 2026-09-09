# Space 分享前云同步兼容修复总结

日期：2026-09-09。工作树：`fix`。用户已确认按推荐方案实施，并要求服务端接口清单与 Apifox 验收方法。

## 已完成改动

- `SunSmart/Common/Network/NetworkRequest.swift`：Site/Space 同步请求保留 Moya 生成的普通 JSON，不再按 1 KB 阈值自动 gzip；清除请求 Content-Encoding 及同步请求的旧 Content-Length，继续保留响应压缩协商。
- 网络结果适配保留字符串业务码的可读取信息及诊断输出。`parse_error` 在 HTTP 400 下使用 400 作为整数错误码，不再变成 0；非 2xx 响应不能因正文写了成功而被判为成功。业务码从已有 responseBody 中提取，没有改变错误数据结构。
- `SunSmart/Common/Data/SpaceConfigurationSafety.swift`：仅对 HTTP 400、字符串业务码 parse_error 且没有底层传输错误的明确解析拒绝，结束对应的 prepared 提交。沿用现有 account/region/生命周期/submissionId 检查，保留本地更新、删除日志、确认基线及其他提交。
- 保留已接受提交、超时/断网/5xx/未知 4xx 的回读验证；保留历史 prepared 回执在云端匹配已确认基线时的恢复路径，真实冲突仍受保护。
- 未修改 UI、分享权限逻辑、国际化、资源、target 配置或 SDK；未提交 Git，未对生产服务器发送写请求。

## 自动验证结果

| 验证 | 结果 | 覆盖 |
| --- | --- | --- |
| `python3 scripts/check_network_response_queue.py` | PASS | 生产网络适配器后台解析/主线程回调、字符串 parse_error、HTTP 与业务成功状态冲突 |
| `python3 scripts/check_space_recovery_receipts.py` | PASS | 持久化回执、解析拒绝后无无效回读、本地数据/删除日志保留、旧回调、新提交、accepted 保护、历史基线恢复与真实冲突 |
| `python3 scripts/check_site_entry_performance.py <resolved SDK>` | PASS | Site/Space 大小 JSON、UTF-8、Header/Body 一致、重复准备、响应 gzip 保留，以及现有 SQLite/地址语义验证 |
| Apifox 文件工具本地执行 | PASS | Site envelope、500 节点 Space envelope、gzip 往返无损、文件字节/散列、截断 gzip、无效 JSON、拒绝覆盖目录和未解析变量；无网络请求 |
| `git diff --check` | PASS | 已跟踪改动的空白检查 |

上述 SDK 测试路径与实际构建解析出的版本均为 `release` 的 `a6246b1b0409824a3227a9c7cad8140219feb182`，未改变 Package.resolved。

以下五个品牌均直接执行 `xcodebuild -workspace SunSmart.xcworkspace -scheme <scheme> -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`，全部 **BUILD SUCCEEDED**：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart
- Lumineux

构建仍有工程既有资源重名、重复编译条目、Info.plist 资源及 AppIntents 等警告，本次未扩大修改范围处理。

## 服务端交付

确定需要修复请求解压的两个接口为 POST `/sitespace/sync/siteprops` 与 POST `/sitespace/sync/spaceprops`。Site 路径同时用于首次创建与后续同步，须覆盖相应请求形态。

详见 [服务端同步接口修复清单与 Apifox 验收](260909_2033_server_sync_gzip_apifox_acceptance.md)。该文档包含完整 envelope 对照、binary 请求设置、9 组正反向用例、回读字段、独立拓扑异常排查与分地区验收要求。

配套工具为 `scripts/prepare_apifox_sync_fixture.py`，接受完整测试请求 JSON 并在新目录生成 identity/gzip/负向文件及 manifest。它不会构造或发送业务写请求，也不验证账号或业务字段是否获得服务器认可。

## 仍需真实环境验收

1. 更新 App 后，测试原有失败回执恢复及兴东类似的 500 节点上传，确认不再出现 UTF-8 gzip 400，回读配置匹配，分享流程可完成。
2. 普通 JSON 上传比 gzip 流量大，需要测量真实请求大小、服务器请求上限及当前 10 秒超时窗口。构建/本地测试不证明实际服务器接受或性能达标。
3. 服务端须保证 `400 + parse_error` 确实发生在业务写入前，并通过 Apifox 坏压缩体/坏 JSON 后回读不变的用例验证。
4. 历史 prepared 回执如果遇到真正云端冲突，仍会阻止盲目覆盖；本次不批量清理旧回执或删除保护数据。
5. 真正 gzip 上传使用一个尚未写入的新版本做成功回读，才算服务端 gzip 修复完成。当前 App 普通 JSON 上传成功不能替代这项验证。
6. 另一个 Space 的 invalidRemoteTopology 继续作为独立数据完整性问题处理。

本次已完成 App 代码、自动回归、五品牌 generic iPhoneOS 构建及 Apifox 方法文档。未声称服务器已部署、Apifox 已连接真实服务测试或真机分享已验收。
