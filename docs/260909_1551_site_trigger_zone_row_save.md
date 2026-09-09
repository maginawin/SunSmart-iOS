# Site Trigger Zone：选中行独立 Save

日期：2026-09-09。

## 界面调整

- 仅 Site Trigger Zone 选中行显示 Test、Reset、Delete、Save，顺序从左到右；取消选择后隐藏这些按钮。
- 复用现有行头的 Save 按钮和 `Save` 国际化 Key；英文为 Save，简体中文为保存。
- Site 专用行头将 Save 放在最右边，Delete 移至其左侧。按钮尺寸、边框、圆角、背景和禁用态沿用共享组件。
- 标题增加右侧约束和截断规则，给四个按钮保留空间。原 Group/Space 行头布局和行为不变。
- 保存期间禁用行 Save，切换选中项不会改变已经捕获的 zoneId。成功后保留选择，失败重试保留原 Zone 范围。

## 保存范围

- 行回调携带稳定 zoneId，通过独立的范围参数进入 SiteTriggerZoneCoordinator。
- 请求仍调用 `/sitespace/update/siteprops`，提交 `props.extensionData`，不增加未经约定的单 Zone 服务端接口。
- extensionData 的 triggerZones 仍是完整数组：以服务器已知数据为基础，仅替换或追加本次选中的 Zone；其他 Zone 保留服务器版本，不混入其未保存的本地修改。
- 服务器回读确认本次提交后，保留其他 Zone 的待提交数据；该次 Save 随即结束，不继续循环保存其他 Zone。
- 同一 Site 已有属性上传时，行 Save 等待其结束，再执行自身范围，不能把前一个请求的成功当作当前 Zone 保存成功。
- 空 Zone 创建和删除继续沿用此前确认的即时持久化/属性提交方式；Site 页面的全量同步仍保留 extensionData。

## 后续边界

当前首期仍只有空 Zone 和添加面板展示。行 Save 本轮接入的是按 Zone 限定的云端属性保存；非空成员仍受原有“不支持编辑”保护。后续成员更新应以该 zoneId 创建独立编辑及设备同步会话，补充该 Zone 全部成员 Spaces、旧新影响范围的权限预检与网络切换，不能转回整页 Mesh SAVE。

未运行构建、测试、真机布局或接口联调，按用户要求由用户手动验收。建议手动关注选中/切换、Zone 100 标题、四按钮排列、iPhone/iPad 窄窗口及保存失败后的原 Zone 重试。
