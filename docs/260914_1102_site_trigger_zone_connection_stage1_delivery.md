# Site Trigger Zone 连接阶段 1 交付记录

日期：2026-09-14。范围：用户确认的阶段 1；正式版开放 Quick add Start 连接入口。

## 结果与行为

- Quick add 首次选中可用 Space 时保持 `Click to start`。点击 Start 后检查目标 Mesh UUID 与 NetKey；已连接则复用，未连接则进入 `Connecting`。SDK 网络装载失败或 30 秒内未连接成功时进入 `Connection failed`，由 Retry 显式开始新一轮连接。意外断开同样进入失败状态，不自动重试。
- 从 Quick add 切换到 Trigger add / Manually add，未连接时自动连接；Connecting、失败、已连接状态保持。两种分类中换 Space 时停止旧会话并自动连接新 Space；Quick add 中换 Space 则断开旧 Space，让新 Space 等待 Start。切 Zone 不断开同一 Space，Quick add 恢复到需要 Start 的状态。离开页面时只在当前 Mesh 身份仍属于旧 Space 时断开，并尝试恢复 Site Primary 网络上下文。
- 三个分类共用连接状态卡片、英文与简体中文文案。正式版连接成功后显示“Adding devices is not available yet.”；阶段 1 不会监听感应消息、添加 Site Zone 成员或提交设备配置。Quick add 的 Pause/Stop 与草稿保存留待阶段 2，因为本阶段尚无 Adding 状态。
- 会话用串行切换与 request token 排除旧 Space 的连接回调；传输层可注入，以便独立测试成功、断线、超时、Retry、切换与过期回调。SDK 全局连接上下文仍由 `MeshLibManager` 管理，会话每次只按 Mesh UUID + NetKey 校验和清理自己的目标。

## 验证

- SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 五个 scheme 的 Debug iPhoneOS generic 构建通过；SunSmart Release iPhoneOS generic 构建也通过，确认正式版编译包含 Start 入口。`scripts/check_site_trigger_zones.sh`、中英文 strings 校验、`git diff --check` 通过。
- 在连接的 iPhone 15 上运行隔离 UIKit 验证应用：连接会话状态探针英文、中文均为 `PASS`；Connecting / Connection failed / Retry / Connected 的布局检查覆盖 320、393、768pt 宽与三种分类，中英文均未报告状态卡片越界、文字裁切或与提示重叠。验证图由应用内 UIKit 探针生成，未用 Computer Use 验收。
- 原有候选布局探针在 480×480 模拟尺寸仍报告面板高度压缩；主工程 iPhone 仅声明竖屏，该尺寸不属于支持的 iPhone 方向。原有帮助页返回交互探针也报告失败；两项均与新增连接状态探针分开记录，未据此声明整体候选探针通过。

## 后续阶段边界

阶段 2 实现 Proximity 消息筛选、Zone 本地草稿、Save 持久化、切 Zone/退出的未保存提示，并使 Quick Stop 保留连接。阶段 3 实现跨 Space 的设备同步与真实 Mesh 联动。本阶段没有合格 Space + 实体 Mesh 设备的端到端连接实测，发布前仍应在具备该环境的真机上走一遍 Start、超时/断线、Retry 和切 Space。
