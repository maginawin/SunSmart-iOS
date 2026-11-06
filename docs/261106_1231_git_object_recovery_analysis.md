# SunSmart Git 对象缺失诊断、恢复方案与执行记录

记录时间：2026-11-06，Asia/Singapore；12:46 更新执行结果。用户已确认“按此方案先恢复可恢复的 9 个工作树”。本轮完成该阶段，不涉及业务代码、SDK、数据库或 export JSON 结构变更。

## 结论与未完成项

- 已恢复当前 `feat/daylight-saving-261024` 及另外 8 个工作树。直接使用原仓库即可读取 HEAD、全部索引对象、HEAD 历史、status 与 diff，不再依赖临时对象库或禁用索引的命令参数。
- 已完整备份共享 `.git` 和全部 11 个工作树；随后补入 3 个经过验证的对象文件，并将失效 `multi-pack-index` 移至备份目录。分支引用、reflog、暂存内容、工作文件和原有残留对象均已核对保留；最终仅更新本文档记录结果。
- `4g-dfu`、`accuracy` 及记录中的 1416 个历史对象仍未恢复。共享库完整 fsck 仍退出 26，其问题集合与恢复前隔离验证完全一致；本轮没有继续执行旧历史抢救。
- 直接故障是主要对象包及配套索引缺失。缺失由哪条命令或哪个程序造成，目前没有足够证据。

## 诊断时的状态与直接证据

| 项目 | 当前检查结果 |
| --- | --- |
| 目标目录 | `/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/feat-daylight-saving-261024` |
| 分支 | `feat/daylight-saving-261024` |
| HEAD | `59be4df7ffe3427af1fad1a45a6514e2813eb1ed` |
| 共享 Git 目录 | `/Users/maginawin/Developer/iOS/YKH/sun-smart/.git` |
| 远端 | `github.com:maginawin/SunSmart-iOS.git`，只读查询的 `refs/heads/dev` 与本地 HEAD 完全一致 |
| 当前工作文件 | 7095 个索引条目对应的文件均存在；隔离验证识别出原有 18 个修改文件、7 个未跟踪文件；暂存区相对 HEAD 无差异 |
| 原始故障 | `git cat-file -t HEAD` 失败，`git status` 报 `bad object HEAD`；7095 个索引条目涉及的 6296 个唯一对象全部不可读 |
| 原始完整检查 | 禁用失效 multi-pack-index 后，`git fsck --full --no-progress` 仍退出 26，存在大量缺失对象、无效引用与 reflog 引用，故障不只是加速索引问题 |

缺失的主要包为 `pack-1678dad774fa539020acf0f5f0c06ad5d5ade938`：`multi-pack-index` 仍记录它的 `.idx` 名称，但该 `.idx` 及对应 `.pack` 文件都不在对象目录中。

现存正式 pack 只有 `pack-03e6a6b27fc64e7125196d179bb5d9210aa0ae89`，含 87 个对象；另有 1 个松散对象。对象目录没有配置 alternates，也没有相关 Git 环境变量将对象读取重定向到其他路径。目录和现有 pack 可读取，不是整个目录的读取权限被拒绝。

“6296 个对象不可读”描述的是 Git 保存的版本内容，并不表示工作目录有 6296 个文件被删除。

## 原因判断及证据限制

1. 对象目录、现存正式 pack 和 `multi-pack-index` 在 2026-11-06 12:08:22 附近有创建或修改记录。这是排查时间线的线索，不能直接当作删除事件审计记录。
2. 目录中有 3548 个 `tmp_pack_*` 文件，总计约 8.27 GB。最早、中间和最新的三个样本均有 PACK 头，但全文件 SHA-1 与末尾摘要不匹配，不能直接当作完整 pack 使用。另有 `multi-pack-index`；`git count-objects` 报告的 3549 项 garbage 包含这些临时文件及索引计数差异，不等同于 3549 个完整备份包。
3. 打包/维护异常中断、并发操作或外部删除都属于候选原因，当前没有证据将责任归给具体工具。不能仅凭临时包多，就认定本次主包缺失由这些临时包导致。
4. 有限范围的近期 shell 历史和当天相关时间窗口的本地任务记录中，没有找到直接对应的清理命令；这不排除 GUI、后台任务、其他终端或未保留记录中的操作。用户对该时段是否进行过清理没有明确记忆。
5. 当前磁盘约有 146 GiB 可用空间；没有证据证明故障时发生过空间耗尽。`tmutil listlocalsnapshots /` 没有列出本地快照；废纸篓读取受权限限制，尚未核对。

## 隔离恢复验证

恢复来源目录：`/tmp/sunsmart-git-recovery-20261106-1n2nbb93/remote.git`。这是远端完整 mirror 下载的恢复来源，不是原仓库或未提交文件的备份，也不是正式替代仓库。

- 下载完成，远端副本包含 26098 个对象，`git fsck --full --no-progress` 退出 0。
- 仅在检查命令的环境中设置 `GIT_ALTERNATE_OBJECT_DIRECTORIES` 指向该副本，并使用 `-c core.multiPackIndex=false` 绕过原仓库失效的加速索引；没有写入原仓库配置或 alternates 文件。
- 当前工作树的 `git status --short --branch`、`git diff --stat`、`git diff --cached --stat` 均成功。
- 以下工作树的 HEAD、全部索引对象及 status 均可读取：主工作树 `dev`、`feat-daylight-saving-261024`、`feat-device-scene-261028`、`feat-HDB-261020`、`fix-llh-sync-261028`、`fix-SR-BL2421-MINI-261027`、`improve-iv-update-261016`、`Lumineux`、`release`。这不表示其全部 reflog 历史都已验证完整。

| 仍不完整的工作树 | 缺失 HEAD | 索引仍缺失的唯一对象 |
| --- | --- | --- |
| `4g-dfu` | `3c7851b2af3693292078a667ad6cb913a429559f` | 15 |
| `accuracy` | `3822cb4b315c88d45ba62fcdea57dce908438620` | 23 |

原 `multi-pack-index` 记录 27601 个对象。远端副本加本地残留对象能够提供其中 26185 个，仍缺 1416 个；这些对象未包含在本次远端 mirror 中，不能断言它们从未推送过。原仓库在借用远端对象后的完整 fsck 仍退出 26。

诊断产物位于同一临时目录：`worktree-coverage.json`、`missing-midx-oids.txt`、`overlay-fsck.txt`。临时目录不宜作为唯一长期备份。

## 已确认的实施范围

第一阶段恢复当前开发和可恢复工作树，第二阶段保留证据继续寻找旧历史。本轮已完成下列第 1 至 5 项；第 6 项不在本次实施授权范围内。

1. 写入前重新核对分支、索引和文件变化，确认共享仓库没有其他任务执行写入或清理。将共享 `.git`、各工作树当前文件及未提交状态备份到独立位置；保留所有残留和临时对象文件。
2. 将独立副本中已经通过校验的对象包及索引补入共享对象库。使用临时文件及原子安装方式，不覆盖现有对象包，不改变任何分支、reflog、暂存区和工作文件。
3. 将引用已缺失包的 `multi-pack-index` 备份移出生效位置，使 Git 从实际存在的包读取。需要重建加速索引时仅基于已验证包进行，不运行 prune/gc 清理。
4. 不借用临时目录重新运行当前工作树的 HEAD、索引、status 和 diff 检查，并检查另外 8 个可恢复工作树；比对修复前后的工作文件、索引与分支引用。
5. 重跑共享库完整 fsck，明确报告仍缺对象，不通过删除旧分支、reflog 或重置索引来消除错误。
6. 对两个旧工作树及剩余历史对象，继续从其他完整克隆、备份、可访问的废纸篓或临时包中抢救；临时包的任何重建和提取都先在副本上进行，按对象哈希验证。若只能取得工作文件，可以保存代码内容，但不能冒充已恢复原始提交历史。

实施写入的是 11 个工作树共用的对象库；没有同步各工作树分支或修改业务代码。用户明确确认第一阶段后执行，当前阶段已结束。

## 第一阶段执行结果

备份目录：`/Users/maginawin/Developer/iOS/YKH/sun-smart-git-recovery/20261106_124220`。

- `worktrees/dev/` 保存主工作树及原始共享 `.git`；`worktrees/` 下其余目录保存另外 10 个工作树的完整目录副本，包含目录内忽略文件。使用同盘 APFS 写时复制，符号链接按链接保存，外部链接目标未展开复制。复制后逐项核对内容 SHA-256、权限及链接目标。
- `verified-remote.git/` 保存通过校验的远端 mirror，恢复来源不再只存放于 `/tmp`。
- `quarantine/multi-pack-index` 保存本次移出的失效加速索引；其内容与原始备份一致。
- `evidence/` 保存恢复前目录清单、文件摘要、状态与 diff 摘要、实际操作清单和验证结果。

12:43:58 完成对象安装。共享对象目录新增以下三个文件，逐个校验 SHA-256，并通过同目录临时文件原子安装：

- `pack-b0ccb6d254c5e261e6560775305944fecbc34e72.pack`
- `pack-b0ccb6d254c5e261e6560775305944fecbc34e72.idx`
- `pack-b0ccb6d254c5e261e6560775305944fecbc34e72.rev`

恢复后验证没有设置 `GIT_ALTERNATE_OBJECT_DIRECTORIES`、没有禁用 `core.multiPackIndex`，也没有创建永久 alternates。以下检查全部成功：

| 工作树 | 唯一索引对象数 | HEAD 历史遍历对象数 | status / 暂存 diff / 未暂存 diff |
| --- | ---: | ---: | --- |
| 主工作树 `dev` | 6296 | 25943 | 成功，结果与恢复前隔离读取一致 |
| `feat-daylight-saving-261024` | 6296 | 25943 | 同上 |
| `feat-device-scene-261028` | 6293 | 25891 | 同上 |
| `feat-HDB-261020` | 6357 | 24225 | 同上 |
| `fix-llh-sync-261028` | 6359 | 24273 | 同上 |
| `fix-SR-BL2421-MINI-261027` | 6357 | 24225 | 同上 |
| `improve-iv-update-261016` | 5941 | 23152 | 同上 |
| `Lumineux` | 6357 | 24225 | 同上 |
| `release` | 6357 | 24225 | 同上 |

使用 `git rev-list --objects --missing=print HEAD` 检查这 9 个工作树的 HEAD 历史，均退出 0，未发现缺失对象。各自 HEAD 均保持原值，所有索引对象可读。

全目录核对发现两个索引文件在本轮期间刷新：`feat-HDB-261020`、`fix-SR-BL2421-MINI-261027`。其索引条目差异为 `ctime` / `dev` 文件统计缓存；逐条比较所有 11 个工作树的路径、对象、stage、模式及标志，暂存语义一致，其余 debug 字段也一致。原始索引已备份，没有为了恢复旧缓存而覆盖当前索引。

最终目录摘要核对通过：除上述三个新增对象文件、移出的加速索引以及两个索引缓存刷新外，共享库和所有工作树的内容、权限及链接目标未发生变化；分支、reflog、现有 pack、3548 个临时 pack 和两个待抢救工作树的文件均保留。该核对完成后，仅更新本文档。

共享库完整 `git fsck --full --no-progress` 仍退出 26，共 1591 行结果，与修复前隔离检查排序后的结果完全相同；原记录中的 1416 个历史对象仍缺失。`4g-dfu` 仍缺 HEAD 和 15 个索引对象，`accuracy` 仍缺 HEAD 和 23 个索引对象。本轮没有删除引用或 reflog 来消除这些错误。

验证证据文件：`verification-worktrees.json`、`verification-files.json`、`verification-indexes.json`、`fsck-summary.json`、`fsck-after.txt`。业务代码审查、App 构建及运行验收不属于本次 Git 恢复阶段。

## 操作注意与验证边界

- 原库尚缺对象时，避免执行 `reset --hard`、`clean`、`gc`、`prune` 或直接删除 `.git`/临时 pack；这些操作不属于本次恢复方案。
- 不用新 clone 覆盖现有目录，也不把远端 mirror 的 refs 覆盖到本地，以保留未提交改动和本地分支线索。
- 本轮未运行 App 构建或业务测试；Git 恢复验证不代表代码审查通过或业务功能验收通过。
- [Git fsck 官方文档](https://git-scm.com/docs/git-fsck)说明缺失对象必须从备份或其他归档寻找；fsck 本身用于诊断，不会自动还原缺失内容。
- [Git gc 官方文档](https://git-scm.com/docs/git-gc)说明并发写入时存在对象清理风险。这是一般风险说明，不是本次事故由 gc 引起的证据。

