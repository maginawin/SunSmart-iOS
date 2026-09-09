# Site Trigger Zone：extensionData 字段调整

日期：2026-09-09。本文已按用户最终确认更新为正确拼写 `extensionData`，文件名保留以维持既有引用。按用户要求，将接口中原拟名为 `siteData` 的 Site 扩展字段统一改为 `extensionData`，内部 `triggerZones` 结构保持不变。

| 场景 | 字段路径与接口 |
| --- | --- |
| Site Trigger Zone 页面添加、更新、删除及失败重试 | `/sitespace/update/siteprops`，请求 `props.extensionData` |
| Site 页面同步整个 Site | `/sitespace/sync/siteprops`，请求中的 Site 对象保留 `site.extensionData` |
| 获取整个 Site | `/sitespace/get/siteprops`，读取返回 Site 对象的 `extensionData` |
| 获取指定 Site 属性 | `/sitespace/retrieve/siteprops`，请求字段改为 `props.extensionData`，读取 `data.props.extensionData` |

已调整导出字段、导入存储入口、Zone 属性更新请求及属性读取请求。属性接口返回数据仍通过统一存储入口合并。代表完整 Site 对象的 `SiteData` 类型、`siteData` 局部变量及 API 参数名保留，避免将整个 Site 对象误改名为扩展数据。

本地数据库中的扩展内容和待提交快照不包含外层接口字段名，因此本次仅调整网络映射，不需要因改名清空或重建已有 Zone。

新建/首次导入旧数据缺少 `extensionData` 时使用默认空 Zone；后续响应缺字段不清空已保存数据。Site 上限保持 100，Space 上限保持 32。两条同步路径的职责按用户已确认方案保持不变。

本次未运行构建、测试、真机验证或接口联调，交由用户手动验收。
