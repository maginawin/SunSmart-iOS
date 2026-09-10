# 本分支工程引用调整与合并前验证

日期：2026-09-10。分支：site-trigger-zone。

## 实施范围

按用户最新要求，在当前分支调整工程文件并构建，由用户手动测试后自行合并 dev。本次不执行上一份分析文档中建议的实际 merge。

唯一工程改动为 `SunSmart.xcodeproj/project.pbxproj`：将段末尾的 45 条 SiteTriggerZone PBXBuildFile 定义与 9 条 PBXFileReference 定义，分别移到对应段的 SiteViewController 定义之后。避开 dev 调整段末尾既有条目的位置。

共 54 行移动，新增与删除的行逐字一致。没有更改 UUID、文件路径、Group children、Sources 列表、版本号、资源、本地化、SDK 或业务代码，也没有提前引入 dev 的 gzip 改动。

## 冲突与工程结构验证

验证基于 HEAD `c8a64d92`、本地 dev `7730b7f8`、共同祖先 `8322422ad613f338a43c20aa9b90aff0ef417558`。未 fetch。

- 修改前后工程均可经 plutil 解析，解析后的完整对象严格相等，证明只有文本位置调整。
- 工程对象 UUID 无重复。
- 五品牌各自的 Sources 列表仍包含全部九个 SiteTriggerZone 源文件，且这些文件没有重复编译引用。
- 对双方共同修改的两个文件逐一以工作区内容、共同祖先和 dev 做临时三方合并：project.pbxproj 与 NetowrkReqeustApi.swift 均返回 0，无冲突。
- 预演所得工程对象严格等于当前工程加上 dev 的十个版本号配置更新，没有丢失本分支新增对象或列表。
- git diff --check 通过。

预演只操作临时副本，没有生成 Git 提交，也没有改变索引或启动实际 merge。上述无冲突结论以本次调整纳入本分支提交、且 dev 保持该提交为前提。

## 自动验证

现有 `bash scripts/check_site_trigger_zones.sh` 通过：覆盖标识、100 个 Zone 上限、兼容、待同步、冲突与重启，以及 29 个界面模型样本、角色权限、完整性、受限摘要、同步范围和模式隔离。

所有构建均直接调用 xcodebuild，使用 SunSmart.xcworkspace、对应 scheme、Debug、iphoneos、generic/platform=iOS、CODE_SIGNING_ALLOWED=NO。未使用 Simulator、shell 包装或日志重定向。

| Scheme | 构建结果 |
| --- | --- |
| SunSmart | BUILD SUCCEEDED |
| Archipelago | BUILD SUCCEEDED |
| SLG Sync Plus | BUILD SUCCEEDED |
| SylSmart | BUILD SUCCEEDED |
| Lumineux | BUILD SUCCEEDED |

解析的 NordicSigMeshSDK 为 release / a6246b1。构建输出含现有资源符号与 AppIntents 等警告，本次未扩大范围处理。

## 交接

用户接下来在本分支手动验证功能。测试通过后，先将本次 project.pbxproj 调整提交到当前分支，再手工合并 dev；仅保留为未提交修改时，Git 可能因 dev 也改了同一文件而拒绝合并。

本轮未执行 git add、commit、merge、push 或真机测试。当前构建验证针对本分支，不能替代用户后续功能测试或合并 dev 后的集成验证。
