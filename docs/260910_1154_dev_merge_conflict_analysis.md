# dev 合入 site-trigger-zone 冲突分析

日期：2026-09-10。范围：只分析、预演和生成处理方案，不执行实际合并，不修改工程或业务代码。

## 结论

以当前本地分支引用为准，只有 `SunSmart.xcodeproj/project.pbxproj` 出现冲突，共两块，分别位于 `PBXBuildFile` 和 `PBXFileReference` 段末尾。

当前分支新增 Site Trigger Zone 工程引用，dev 重新排列已有工程对象，两者在同一文本位置发生冲突。对工程对象解析后，dev 相对共同祖先没有新增或删除对象，只有五品牌 Debug/Release 共十个构建配置的 `MARKETING_VERSION` 变为 `1.2.3`；其余工程差异为排列与注释变化。

建议保留 dev 的工程排列及版本号，补回当前分支全部 Site Trigger Zone 新增条目。不能直接整文件选择 ours/theirs，也不能对冲突直接 Accept Both 而不去重。

## 分支与预演依据

| 项目 | 当前结果 |
| --- | --- |
| 当前分支 | site-trigger-zone |
| HEAD | c8a64d92，feat: add site trigger zone view controller |
| 本地 dev | 7730b7f8，release 1.2.3 |
| 本地 origin/dev 跟踪引用 | 同为 7730b7f8 |
| 共同祖先 | 8322422ad613f338a43c20aa9b90aff0ef417558 |
| 当前分支独有提交 | 1 个 |
| dev 独有提交 | 206d2095（gzip 同步接口）与 7730b7f8（版本号） |
| 初始工作区 | 干净，没有 MERGE_HEAD，没有正在进行的 merge |

未执行 fetch；本报告不保证远程服务器在分析期间没有新增提交。使用三参数 `git merge-tree` 只读预演，再将三方工程文件导出至临时目录，用 `git merge-file -p` 核对冲突及候选结果，未改变工作区文件或索引。

## 两处冲突的处理规则

| 冲突段 | 当前分支一侧 | dev 一侧 | 处理方法 |
| --- | --- | --- | --- |
| PBXBuildFile 尾部 | 45 条 SiteTriggerZone 新编译条目，加上 10 条既有 SpaceConfiguration 条目 | 9 条已重新排列的 Sync 编译条目 | 保留 45 条新增项和 dev 的 9 条；既有 SpaceConfiguration 项在前面已有定义，删除尾部重复定义 |
| PBXFileReference 尾部 | 9 条 SiteTriggerZone 新文件引用，加上 2 条既有 SpaceConfiguration 引用 | 1 条已重新排列的 SyncRetryPolicy 引用 | 保留 9 条新增项和 dev 的 1 条；既有 SpaceConfiguration 引用只保留前面的定义 |

直接 Accept Both 会重复定义以下 12 个 UUID：

- `F26090710000000000000001` 至 `F26090710000000000000005`：SpaceConfigurationIntegrityPolicy 的五品牌编译条目。
- `F26090720000000000000001` 至 `F26090720000000000000005`：SpaceConfigurationSafety 的五品牌编译条目。
- `F26090700000000000000001`、`F26090700000000000000002`：上述两个文件的引用。

重复项的对象内容一致，注释可能因 Xcode 排列而改变；保留 dev 已排列到前面的定义即可。不要删除它们在 Group 或 Sources 列表中的引用。

此外，自动合并得到的 Site Group 九条 children 和五个 Sources 列表各九条新增项必须保留。这部分没有冲突，但只修复对象定义而漏掉列表会导致文件未加入对应 target。

## 业务代码与依赖

- `NetowrkReqeustApi.swift` 是另一个双方都修改的文件，但修改位置不同，可以自动合并。当前分支增加 sitePropsRetrieve 的 extensionData 请求字段，dev 修改响应 gzip 协商范围，两者都要保留。临时三方合并返回 0，已核对两项均存在。
- `NetworkRequest.swift`、`SpaceConfigurationSafety.swift` 及相关网络测试采用 dev 改动，当前分支没有改动这些文件，不存在文本冲突。
- Site Trigger Zone 的模型、存储、导入导出、页面、图片资源和中英文本地化保留当前分支改动。
- 双方均没有修改 Podfile、Podfile.lock 或 Package.resolved；工程对象对比也未发现 Swift Package 引用变化。本次解决冲突无需修改 SDK 或升级依赖。
- 当前检查未发现业务语义互斥：extensionData 属于请求/数据内容，gzip 属于最终传输正文编码。完整运行行为仍需在正式合并后验证。

## 已完成的候选结构验证

只在临时副本中合并冲突并去除重复定义，尚未应用到工程。

1. 候选工程通过 plutil 解析。
2. 以 UUID 为键比较全部解析对象，候选结果严格等于“dev 工程对象 + 当前分支相对共同祖先的全部新增与列表变更”。
3. 重复 SpaceConfiguration 对象与双方原对象内容一致，没有丢失对象属性。
4. 五品牌 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 各自均包含全部九个 SiteTriggerZone 源文件。
5. 没有悬空的显式 fileRef，也没有新增重复 UUID。
6. SLG Sync Plus 的 FSCalendarDelegationProxy.m 和 SylSmart 的 FSCalendar.m 各有一处既有重复编译引用；共同祖先、双方分支和候选结果一致，与本次冲突无关，不纳入修复范围。
7. dev 五品牌 Debug/Release 的版本号 1.2.3 均保留。

临时候选文件：`/var/folders/y1/phq8m2pd29jf7bwfcmq1j9j80000gn/T/site-trigger-zone-merge-analysis-sg3a16ae/candidate.pbxproj`。它仅用于本次结构分析，可能被系统清理；正式处理应复核分支哈希后按上述规则操作。

## 确认实施后的步骤

1. 重新检查 HEAD、dev 和工作区，避免覆盖分析后新增的修改。
2. 执行合并，在生成提交前按上述规则解决两处冲突，保留其他自动合并结果。
3. 检查冲突标记、UUID 唯一性、文件引用、五品牌 Sources 列表和版本号，再执行 git diff --check。
4. 运行 `bash scripts/check_site_trigger_zones.sh` 及 dev 相关回归：check_site_entry_performance.py、check_network_response_queue.py、check_space_recovery_receipts.py。
5. 直接运行 xcodebuild，对五个品牌 scheme 分别验证 Debug / iphoneos / generic/platform=iOS / CODE_SIGNING_ALLOWED=NO 构建，不用 Simulator，不使用 shell 包装或日志重定向。
6. 本次不改 UI 布局；若冲突处理扩展为 UI 修改，则需要另外完成实际布局验证。默认不执行真机测试，自动构建与脚本结果不代表设备、Mesh 或服务器业务验收。
7. 合并提交和推送按用户后续授权处理。

本轮仅新增此分析文档；未执行 merge、git add、commit、push、构建或真机测试。
