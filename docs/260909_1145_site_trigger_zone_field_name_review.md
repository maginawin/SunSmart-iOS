# Site Trigger Zone 字段改名检查与修正

日期：2026-09-09。用户已确认使用正确拼写 **`extensionData`**，源码四处接口字段及相关方案、接口文档已更正。

## 最终字段映射

| 入口 | 字段路径 | 源码位置 |
| --- | --- | --- |
| 完整 Site 导出，用于 Site 全量同步 | Site 对象的 extensionData | SunSmart/Common/Data/ExportData.swift |
| Site 导入及属性响应合并 | object.extensionData | SunSmart/Main/Site/TriggerZone/SiteTriggerZoneStore.swift |
| Zone 页面属性更新 | props.extensionData | SunSmart/Main/Site/TriggerZone/SiteTriggerZoneCoordinator.swift |
| 指定 Site 属性读取请求 | props.extensionData | SunSmart/Common/Network/NetowrkReqeustApi.swift |

Zone 页面增删改及失败重试继续调用 `/sitespace/update/siteprops`；Site 页面仍通过完整导出调用 `/sitespace/sync/siteprops`，保留 `extensionData`。get 导入与 retrieve 的 data.props 响应均经统一存储入口读取扩展字段。

## 文档与兼容说明

- [首期方案](260909_1040_site_trigger_zone_phase1_plan.md) 和 [接口字段说明](260909_1141_site_trigger_zone_extra_data_contract.md) 已同步为最终名称 `extensionData`。
- 原检查发现的字段拼写错误已按用户要求修正，不再作为待处理项。
- 代表完整 Site 的 SiteData 类型和 siteData 局部变量保留；它们不是扩展字段。
- 本地扩展内容和待提交快照不包含外层接口字段名，本次更正不需要清空或重建 Zone。
- 服务端应同样使用 `extensionData`。当前读取按精确 Key 匹配，首次导入缺失该字段时使用默认空列表，后续响应缺字段不清空已有数据，也不确认待提交修改。

本次未运行构建、测试、真机验证或接口联调，由用户手动验收。
