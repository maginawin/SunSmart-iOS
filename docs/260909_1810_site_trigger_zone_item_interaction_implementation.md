# Site Trigger Zone Item 交互实现与验收记录

日期：2026-09-09。依据：用户已确认本轮完整方案，包括整 Zone 权限策略、Test 内存交互范围及重新进入 Test 恢复样例。

## 已实现

- 可编辑 Zone 的设备控件展示仅含 Remove 的现有样式菜单；设备和同步图标独立处理点击，不顺带选中卡片或展开添加面板。
- 整个 Zone 的 Space 清单必须完整、身份唯一，且所有 Space 都具备有效 Owner/Editor 权限。任一 Visitor、No access、未知或未确认授权使整 Zone 设备操作无效。
- Remove 使用 zoneId + spaceId + deviceId 定位；移除最后一个成员后仅清理被操作 Space，重新计算数量、设备行数、分隔线和高度，不清理受限摘要占位。
- 最后一个 Space 消失或 Reset 后保留 Zone ID、名称、合法空项编辑能力和选择，显示现有 72pt No Data；Test / Reset 禁用，Delete / Save 保留。
- Reset / Delete 提供 Cancel / Confirm；取消不改变数据。Delete 删除当前预览项、清理选中态及添加目标，更新显示编号；Zone ID 和预览场景代码保持稳定。
- Space / Zone / No Data 表头的待同步图标都展示同一说明弹窗。内容来自 Figma 600:8816，只有 OK；宽度上限 302pt、正文 12pt/22pt 行高、标题 14pt、按钮 15pt/60pt 高，复用 Title_Color 和现有白色弹窗基底。
- 说明弹窗及预览确认弹窗随所属窗口调整；菜单边缘定位限制在窗口安全区域，旋转时关闭原菜单。
- 新增三个中英文 Key：同步说明、Reset 确认、Delete 确认；复用已有 Remove、标题、OK、Cancel、Confirm。
- 预览变更集中在 Debug 内存状态中处理。每次变更和预览会话更新版本，拒绝失效弹窗回调；不调用真实协调器、Store、网络或 Mesh。
- Remove / Reset 保留待同步含义；空卡片也能查看待同步说明。卡片 Test / Save 仍提示仅供预览，不模拟真实保存或同步成功。
- 每次从真实模式进入 Test 重建 29 个基础场景并选中 D02；返回真实模式恢复真实选择、滚动及添加面板状态。

## 真机发现并修复的布局问题

1. 估算行高在滚动后修正，会导致默认选中的 D02 标题和四按钮移出视口。现在通过生产 Cell 的 Auto Layout 按实际宽度测量并缓存高度，数据/宽度变更时失效；滚动定位包含表头。
2. 多 Space 标题行只有最小高度，导致多个分区分摊高度时存在歧义。标题行固定为原设计 24pt；小数像素余量留在卡片底部，避免多个多行摘要被不确定地拉伸。
3. SRAlertView 正文的水平抗压缩和抗拉伸优先级均为 required，会让内容宽度偏离设计。Site 说明和预览确认弹窗局部降低这两个优先级，明确最大 302pt，并允许正文按窄窗口换行；不改动共享弹窗默认行为。

上述修正限于 Site 专用组件，没有修改 Group / Space 的共享默认交互，也没有更改 SDK、依赖、Auth 或持久化协议。

## 验证方式

状态回归位于 Tests/Site/SiteTriggerZoneItemPolicyTests.swift，覆盖权限、跨 Space 同 ID、最后成员移除、Reset / Delete、过期回调、重新进入预览和列表空态；通过 bash scripts/check_site_trigger_zones.sh 执行，并保留原真实数据契约测试。

实际 UIKit 布局探针位于 Tests/UI/SiteTriggerZoneItemLayoutProbe.swift；对全部非空场景和两种选中状态循环检查 288 / 351 / 398 / 736 / 480 / 320pt 容器宽度、Cell 复用、分隔线、标签边界、标题/按钮坐标、No Data 过渡和弹窗宽度。

真机点击测试位于 Tests/UI/SiteTriggerZoneInteractionUITests.swift。测试宿主位于 /tmp/SiteZoneInteractionValidation，使用当前生产源码和资源，独立 bundle 为 com.sunricher.site-zone-interaction-validation；入口直接加载实际 SiteTriggerZoneViewController，不覆盖原 SunSmart，不初始化登录或 Mesh，也不保存模拟 Site/Space。

已运行设备为 MtestiPhone15（iPhone 15）；MiPAD（iPad Air 第五代）因锁屏尚未运行。不使用 Simulator。

## 验证结果

| 检查 | 结果 |
| --- | --- |
| Site 原数据契约与扩展交互状态测试 | 通过 |
| 五品牌 Debug generic iPhoneOS 构建 | 通过：SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux |
| SunSmart Release generic iPhoneOS 构建 | 通过 |
| Release 预览隔离 | 通过：二进制不包含 SiteTriggerZonePreviewState / togglePreview，Debug 对照包含 |
| 六个受影响生产 Swift 文件的五品牌 membership | 每个 target 各一次 |
| 中英文本地化、git diff --check | 通过 |
| iPhone 中英文点击与布局验收 | 3 项测试通过，0 失败，143.333 秒；含两种语言的全部布局探针 |
| iPhone Reset/Delete 确认框 | 中英文宽度及取消操作通过；英文正文按单词换行 |
| iPhone 旋转结束后的同步弹窗 | 通过：按钮位于窗口内且可点击，截图复核 |
| iPad 真机点击、旋转及实际窗口变化 | 待验收：MiPAD 锁屏，需要用户解锁 |

布局验收包含在 iPhone 真实 UIKit 上改变容器宽度至 iPad 对应宽度；此项不能替代 iPad 实际窗口操作。双设备联合启动被锁屏阻止后已中断，并改为单独运行 iPhone，未将中断任务记为通过。

真机结果包保存在本机：`/tmp/site-zone-interaction-iphone-verified.xcresult`、`/tmp/site-zone-confirmation-iphone-final.xcresult`、`/tmp/site-zone-landscape-screen-iphone.xcresult`。确认框最后的英文单词换行调整位于 Debug 预览分支，通过独立真机宿主重新编译和验收；五品牌/Release 构建已覆盖其余改动。横屏附件使用 XCUIScreen 全屏截图，避免 XCUIApplication 截图在旋转后使用错误裁剪坐标。

已复核并保存代表截图：[英文同步说明](260909_1810_site_trigger_zone_item_screenshots/sync-en.png)、[中文同步说明](260909_1810_site_trigger_zone_item_screenshots/sync-zh-Hans.png)、[剩余一个 Space](260909_1810_site_trigger_zone_item_screenshots/remaining-space-en.png)、[No Data](260909_1810_site_trigger_zone_item_screenshots/no-data-en.png)、[横屏同步说明](260909_1810_site_trigger_zone_item_screenshots/sync-landscape-en.png)、[Reset 确认](260909_1810_site_trigger_zone_item_screenshots/reset-confirmation-en.png)、[Delete 确认](260909_1810_site_trigger_zone_item_screenshots/delete-confirmation-zh-Hans.png)。

## 交付边界

本轮成员编辑交付于导航 Test 模式，真实模式继续保留已有空 Zone 能力及非空数据格式保护。真机 UI 通过不代表真实云端成员持久化、跨 Space Mesh 同步或现场设备操作已实现。

未提交、推送或合并 Git。
