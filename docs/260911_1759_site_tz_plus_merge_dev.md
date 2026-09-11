# site-tz-plus 合并 dev

## 范围与基线

- 当前分支：`site-tz-plus`，合并前提交 `c8a64d9240c6844b06070e319d7cb05ea8546a8b`。
- 合并来源：本地 `dev`，提交 `46389c4a1394432b0dd3e9105dc75e1b3e29b3b7`；执行 `git fetch origin dev` 后确认与 `origin/dev` 一致。
- 开始时工作区干净。在当前分支合入 `dev`，保留两边历史，不修改其他 worktree 的分支，不推送远端。

## 冲突处理

唯一冲突文件为 `SunSmart.xcodeproj/project.pbxproj`，包含两处冲突块，分别位于 `PBXBuildFile` 与 `PBXFileReference`。

`dev` 调整了工程对象顺序、注释并加入时钟恢复相关配置；本分支在同一区域追加 Site Trigger Zone 引用。合并保留 `dev` 的对象定义与配置，以及本分支 9 个 Site Trigger Zone 源文件在五个品牌 target 的引用。两个 Space 配置安全源文件沿用 `dev` 已存在的定义，避免同一对象 ID 重复定义。

合并后的工程文件相对 `dev` 仅增加本分支原有的 108 行，没有删除。结构化检查确认：

- `dev` 的工程对象全部保留；除 group children 和 Sources 成员增加外，其余对象内容一致。
- 本分支独有对象内容原样保留；所有 group 成员及五个 target 的 Sources 均完整保留两边内容。
- 每个品牌均包含 9 个 Site Trigger Zone 源文件，没有新增重复对象或重复编译项。

`NetowrkReqeustApi.swift` 自动合并成功，保留本分支 `sitePropsRetrieve` 请求的 `extensionData` 字段，同时保留 `dev` 扩展的 gzip 响应协商列表。其余变更直接继承 `dev`。

## 验证

- 工程文件 `plutil -lint`、冲突标记与 `git diff --check` 检查通过。
- `bash scripts/check_site_trigger_zones.sh` 通过，包括数据兼容、100-zone 上限、冲突/重启、29 个 fixture、权限和模式隔离检查。
- `python3 scripts/check_network_response_queue.py` 通过。
- `python3 scripts/check_site_entry_performance.py <本次构建解析的 SDK checkout>` 通过，包括地址语义、SQLite snapshot 失效和各区域 gzip 请求编码检查。
- `bash scripts/check_light_information_time.sh <本次构建解析的 SDK checkout>` 通过，包含灯具与网关时钟恢复及中英文本地化检查。
- SDK 沿用锁定的远程 `release` 提交 `a6246b1b0409824a3227a9c7cad8140219feb182`，未修改 SDK 或依赖版本。
- 五品牌 iOS 构建全部通过：SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux，退出码均为 0。
- 构建仍报告资源重名、废弃 API、部分 target 的 Info.plist 资源项与既有 FSCalendar 重复编译项等警告；本次没有扩展修改这些无关配置。

构建直接使用 `xcodebuild`，配置为 Debug、iphoneos、`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`。本次只处理合并与工程引用，没有修改 UI 布局；未执行 Simulator、真机、服务端或实际 Mesh 验收。
