# SLG 设备配置覆盖异常分析与修复

日期：2026-10-14。工作树：`feat-timed-limited-261008`；分支：`feat/timed-limited-261008`；基线 HEAD：`f3af67f1`。

## 结论与本次实施

已确认北美 `/sitespace/ota/configfile` 对请求正文敏感：同一终端环境、同一端点，无正文 POST 返回 HTTP 500；发送 `{}` 后返回 HTTP 200、业务 code 200，并返回正确的 `0A78/2321` 配置。携带 SLG 品牌鉴权头也复现同样结果。单独补 Content-Type 或使用 Apifox User-Agent 不能使无正文请求成功。

用户已明确授权“为所有的 `/sitespace/ota/configfile` 请求增加 body `{}`”。本次仅修改共享 API 的 `.devicesConfig` 参数分支：从 `nil` 改为 `[:]`，使现有 `.requestParameters(..., encoding: JSONEncoding.default)` 路径生成 `{}` 和 `Content-Type: application/json`。适用于 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 全部五品牌，不需要品牌独立分支。

未修改包内设备目录、缓存优先级、请求触发时机、Node 缓存、服务器、固件、SDK 或鉴权配置。前面提供的 SunSmart/SLG 两份诊断脚本也同步补齐 JSON 正文和 Content-Type，Downloads 与 `/private/tmp` 两处副本一致。未提交 Git。

## 根因证据

实际代码入口为 `SunSmart/Common/Network/NetowrkReqeustApi.swift`。全仓定向检查只有一个生产 API 路径声明，Sites 页面通过 `.devicesConfig` 复用它：

1. 修改前 `.devicesConfig.parameters` 返回 `nil`。
2. `task` 遇到 nil 返回 `.requestPlain`，不会生成 JSON 正文。
3. 北美接口对该请求方式返回 HTTP 500，App 的配置加载失败分支直接结束，保留原有配置。
4. 用户提供的可用 wget 命令带 `--body-data '{}'`。单变量对照确认，这个正文是决定性区别。
5. 修改后空字典进入既有 JSON 编码路径，生成字节 `{}`；不需要改变 HTTP method、品牌头或关闭证书校验。

### 北美接口单变量实测

以下均为本机终端的只读 POST 请求；没有关闭 TLS 证书校验，没有上传或修改服务端数据。

| 品牌请求头 | 正文 | Content-Type | User-Agent | 结果 |
| --- | --- | --- | --- | --- |
| 无 | 无 | 无 | curl 默认 | HTTP 500，非 JSON |
| 无 | 无 | application/json | curl 默认 | HTTP 500，非 JSON |
| 无 | `{}` | 无 | curl 默认 | HTTP 200、code 200，154 条记录 |
| 无 | `{}` | application/json | curl 默认 | HTTP 200、code 200，154 条记录 |
| 无 | 无 | 无 | Apifox/1.0.0 | HTTP 500，非 JSON |
| SLG 现有品牌头 | 无 | application/json | curl 默认 | HTTP 500，非 JSON |
| SLG 现有品牌头 | `{}` | application/json | curl 默认 | HTTP 200、code 200，154 条记录 |

所有成功样本的 `0A78/2321` 均为 `categoryName = Driver Lighting`。鉴权值只从项目读取并传给代码指定的北美服务端，没有写入文档、脚本或输出日志。

此前无正文探测中，中国大陆返回成功，北美/亚太/欧洲返回 500；这些结果仅描述那种请求方式，不能表述为相应地区服务整体不可用。SLG 首次默认北美且隐藏地区选择，SunSmart 可以切区，但用户确认 SunSmart 切到北美后界面同样正确，因此不能将本次品牌表现差异直接归因于用户选择了不同地区。

## 配置来源与品牌表现边界

App 不会写回安装包内的 `devices_config.json`。启动时优先读取非空数据库配置；尚未建立运行时列表时才读取包内 JSON；服务器成功响应解析后整体替换运行时列表并保存数据库。这是完整列表替换，不是“包内存在就跳过服务器”，也不是逐 PID 合并。

Classic/Professional Add Device 按广播 CID+PID 读取运行时列表，将 `categoryName` 复制到扫描对象。收到重复广播时会更新该名称，不经过 Node 的关联对象配置缓存。用户样本与原包内记录的 `deviceCategory` 均为 Lighting，已知差异是展示名称，不代表设备能力类型发生变化。

SunSmart 切换地区的回调只刷新 Sites，不重取设备目录；两个品牌的数据库在各自沙盒内。因此“SunSmart 切到北美后名称正确”不等于这次界面一定使用了北美新回包，也可能来自此前成功下载的内存/数据库缓存。这是源码支持的可能解释，尚无手机 HTTP 日志或数据库快照证明现场具体时序。本次已证实的是请求正文兼容问题，不把终端测试等同于两个手机 App 的运行复现。

删除包内 JSON 不会清除旧数据库或触发网络刷新；首次安装无缓存且网络请求失败时，会让扫描设备变为 unknown 并禁止选择。无需为本次修复删除内置配置。

## 验证结果

- 请求构造隔离校验通过：提取修改前后生产 `.devicesConfig` 参数分支和当前生产 `task`，执行仓库中的实际 Alamofire `JSONEncoding`；Moya Task 类型和请求头适配使用轻量替身。确认旧分支正文为 nil，新分支正文精确为 `{}`、method 为 POST、Content-Type 为 application/json；有/无品牌头两种输入均保留原请求头，Accept-Encoding 保持 gzip，未添加请求正文 gzip 编码。该校验不是完整 App 网络栈或真机验证。
- 首次隔离校验被默认 Clang module cache 写权限阻塞；显式使用已授权的 Xcode ModuleCache 目录后通过，没有清理共享缓存或更改业务代码规避问题。
- SLG Sync Plus generic iOS Debug 构建通过，CODE_SIGNING_ALLOWED=NO。直接使用 `xcodebuild`，未使用 Simulator 或连接真机。
- 构建入口：`SunSmartLocal.xcworkspace`；SDK realpath：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`；revision：`2598bd1`，检查时 SDK 工作树干净，没有新增 SDK API 或修改 SDK。
- DerivedData：`/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-timed-limited-261008`。构建进程退出码 0，Build Log Manifest 记录 0 errors、0 test failures、90 warnings，包含依赖并发/弃用等提示。
- 本次仅为共享参数分支修改，没有新增编译条件、资源归属或依赖变化，选择故障品牌 SLG 编译；未重复构建其他四品牌。
- 两份诊断脚本及其副本通过 bash/Python 语法检查；补齐正文后未重复发起同条件网络请求，复用上表已取得的接口行为证据。

人工验收待用户完成：运行本次 SLG 构建，在联网 Sites 页面完成配置请求后进入 Add Device，确认 `0A78/2321` 显示 Driver Lighting；重启后验证目录缓存仍正确。此前只在终端完成接口对照，没有执行 App 真机安装、抓包或界面验收。

## 保留的关联问题（不在本次实施范围）

- 配置请求失败静默，Sites 下拉刷新、切区、普通返回页面不重取配置；可能缺少失败恢复机会。
- Node 首次读取的配置缓存不随全局目录更新失效，可影响已入网设备的详情、型号、图标等；不能拿它解释 Add Device 的扫描查表链路。恢复流程有显式赋值，后续修复需保留其语义。
- `saveAll` 先删后逐条写，没有事务且忽略逐条失败，网络调用方也未检查保存结果。
- `data.arrayValue` 和 `compactMap` 可将异常响应转为空或不完整列表；合法空目录及坏项的处理需明确接口契约，不能直接放宽或整体拒绝。
- Node 按 PID 查找与扫描按 CID+PID 查找不一致，是独立身份匹配风险，目前没有证据表明它造成此次名称差异。

这些问题未修改、未宣称解决。本次范围按用户明确授权收敛为全品牌 configfile 请求发送 `{}`。
