# Space 上传快照核对与 Apifox 请求文件

> 后续核对：原快照及据此生成的请求均缺少 netKey/appKey，只能作为失败请求样本；“完整”仅指原样复制快照，不代表满足接口必填字段。详见 [密钥缺失分析与修复计划](260910_1413_space_export_missing_mesh_keys_analysis_plan.md)。

## 核对结果

扫描用户提供的 2026-09-10 14:00:56 App 数据容器，共发现 10 份 last-complete-export.json，仅一份 uuid 匹配目标 Space。

- 来源根目录：`/Users/maginawin/Downloads/com.azoula.sunsmart 2026-09-10 14:00.56.775.xcappdata/AppData/Library/Application Support/SpaceConfigurationRecovery`
- 匹配子目录：`d5c04296e7a45541ef578d216b003a116cbf60fdcc42805adc2f867630d1720d`
- 文件名：`last-complete-export.json`
- Space ID：`E335D681-CB9B-48C1-8A6F-223706D4E70D`
- Space 名称：`Space 1 trigger`
- updateTimestamp：`1789019619`，比原日志第一次待确认提交 `1789019527` 晚 92 秒。
- nodes 数量和 deviceCount 均为 2。
- C007 第一个 Group Zone addresses 为空；前两个 Space Trigger Zone 均只有 C00A 下的 162、165，符合原日志三处引用清理后的拓扑。
- 同名恢复状态文件的 account、siteId、spaceId 与日志一致；当前没有 submission 对象。这不能单独证明上传成功。

## 请求文件

已生成至 `/Users/maginawin/Downloads/temp/sunsmart-apifox-260910_1402/`：

- `space-upload-body.json`：完整 JSON 请求，按当前接口包装 siteId、spaceId、userId、spaces；spaces[0] 保留原快照的全部字段。
- `space-upload-body.json.gz`：上述 JSON 的真实 gzip，用于请求体解压兼容性测试。

这些文件含快照原有 Mesh 配置，存放在仓库外；未在文档或终端输出密钥。未新增 Auth 字段。

接口：POST `https://www.mericher.com/srv2/sitespace/sync/spaceprops`。

普通 JSON 请求设置 Content-Type: application/json，移除 Content-Encoding。gzip 请求选择 binary 文件体，设置 Content-Type: application/json 和 Content-Encoding: gzip。两者可设置 Accept-Encoding: gzip。

## 验证与边界

程序核对请求 spaces[0] 与原快照解析结果完全相等，并验证 gzip 解压后与 JSON 文件逐字节相同。JSON 排版和 gzip 实现会影响字节长度，因此生成文件不是 App 原始网络请求的逐字节副本。

此快照版本晚于日志第一次提交；不能伪装成该次原始请求。原容器只读，未修改业务代码或请求服务器。生成文件可用于用户在 Apifox 中发送当前快照的测试。
