# 离线新建 Site 时区未同步提示修复总结

## 修复结果

离线新建 Site 时，App 使用本地时区初始化 `site.timezone` 的同时，会为该时区创建 `.timezone` pending。重新进入 Edit Site 后，时区右侧会展示 `Not synced to server`，其点击行为仍然只服务于 `Update Site time zone`。

Edit Site 的提示条件已明确限定为 `pendingSitePropsMask` 包含 `.timezone`。Site 名称、图片等其他属性未同步，不会触发该时区提示。

## 实现方案

1. 新建 Site 时，将本地默认时区标记为 `.timezone` pending，并记录与本次本地 Site 数据相同代际的 pending timestamp。
2. Edit Site 仅根据 `.timezone` pending 决定是否展示 `Not synced to server`，不使用 Site 整体上传状态。
3. 首次 Site Add 请求成功后，使用请求发出时捕获的不可变时区与时间戳快照核销 `.timezone` pending。
4. 仅当当前本地时区、pending timestamp 与已成功上传的快照完全一致时才核销；若上传过程中用户又修改了时区，则保留较新的 pending，避免误判为已同步。
5. 核销只移除 `.timezone`，不会清除同一 mask 中的其他 pending 属性。

## 保持不变的边界

- Site clone 流程不新增 `.timezone` pending。
- Site 名称、图片或其他数据未同步不会触发时区右侧提示。
- 后续普通 Site Upload 的既有 pending 处理不扩展为 Site 整体同步提示。
- 未修改本地化、资源、target 配置或 NordicSigMeshSDK。

## 验证结果

- `SitePropsEditPolicyTests`：通过。
- `SiteTimeZonePersistenceContractTests`：通过。
- `SiteTimeZoneUIContractTests`：通过。
- `SitePropsAPIContractTests`：通过。
- `scripts/check_site_sync_gateways.sh`：全部通过。
- `git diff --check`：通过。
- SunSmart generic iPhoneOS Debug 无签名构建：通过。
- Archipelago generic iPhoneOS Debug 无签名构建：通过。
- SLG Sync Plus generic iPhoneOS Debug 无签名构建：通过。
- SylSmart generic iPhoneOS Debug 无签名构建：通过。

## 尚需真机/环境验收

- 真机断网新建 Site、退出并重新进入 Edit Site，确认提示展示及点击弹窗行为。
- 恢复网络后确认首次 Site Add 成功会清除对应时区提示，并由服务器正确保存、回读时区。
- Site Add 请求进行期间再次修改时区，确认较新的 `.timezone` pending 不会被旧请求成功结果清除。
