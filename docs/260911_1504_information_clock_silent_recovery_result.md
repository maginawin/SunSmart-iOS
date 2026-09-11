# Information 时间读取静默补偿实施记录

日期：2026-09-11。用户已确认实施范围，并明确要求不执行真机验收。

## 最终行为

- Gateway / Light Information 进入页面和点击时间行继续读取 Date-time、timezone；两者来自一次 TimeGet。
- 时间读取、离线、绑定、写入、回读、本地保存及该时间链路的 Gateway 云同步失败不再显示错误 HUD。
- 首读成功直接显示设备实测数据，不因时区不同而自动写设备。
- 读取超时或设备返回未知时间时，满足连接、权限、AppKey 和 Model 能力要求才补偿一次；已知 Time Server 未绑定则直接进入恢复。
- 恢复顺序为：检查 Time Server / Time Setup Server，分别补绑缺失 Model，发送 TimeSet，确认非零时间及目标偏移，再执行一次 TimeGet，最后验证并保存。
- 即使两个 Model 都已绑定，写时间仍检查配置权限。Light 使用所属 Space 的设备编辑权限，Gateway 使用现有 SiteData.canConfigureGateway。
- 使用设备所属 Site 的有效、可编码时区；Site 缺失、时区缺失或无效时回退发送时手机时区，复用现有 SiteTimeSetMessageFactory。Site 仍采用存储的固定 UTC 偏移。
- 在绑定完成后生成当前时间，使用目标 Model 所在 Element 地址和本轮捕获的 AppKey 直接调用 SDK 发送，避免 Model 多 Key 排序选错 Key，也不进入 App 公共消息队列等待。
- TimeSet 的响应不直接作为最终成功；最终回读需时间有效、目标偏移一致、误差不超过 30 秒。失败不循环恢复，后续主动点击可以重新开始。
- Gateway 验证成功后沿用本地保存和云同步；Light 只保存本地。没有修改 Site 时区。

## 生命周期与数据保护

- Information 使用共享恢复状态机及可替换传输接口；各请求阶段校验回调 ID，迟到或重复回调不能推进其他阶段。
- 每阶段校验原 MeshNetwork 对象、Node 归属、当前 Proxy Ready 会话、当前 AppKey 及写入权限。Gateway 继续限制为该 Gateway 直连；Light 可经其他 Proxy 路由。
- 页面退出、导航容器关闭或协调器释放后，不再发送后续补偿命令或更新页面。已提交给 SDK 的命令可能已经在设备执行，不能撤回。
- 同 Site、同 Node 的 Information 与 Gateway 详情时间操作互斥，避免 TimeStatus 等待冲突。忙时本轮自动读取静默跳过，用户可点击时间行重试。
- 增加请求结束期限：正常读取等待 10 秒；额外的 15 秒兜底用于结束被其他调用取消的时间响应等待；绑定使用 45 秒兜底。这些期限不会启动循环重试。
- SDK 收到 TimeStatus 会先更新 Node。适配器仅在持有原 Node 的操作所有权且缓存仍对应本响应时恢复已确认快照；发现不同的新缓存值时停止，避免旧备份覆盖新结果。恢复保存失败也直接静默结束。
- 未验证的中间 TimeSet 响应不作为 Information 成功数据上传。SDK 全局接收、并发发布、设备实际执行及服务器结果仍属于设备/服务器验收范围。

## 文件与影响范围

- 新增 `SunSmart/Main/Device/InformationClockRecovery.swift`：恢复状态机、传输适配器、同设备操作互斥和缓存校验。
- GatewayTimeInformationCoordinator / LightTimeInformationCoordinator 接入共享恢复，各自保留连接入口和持久化副作用。
- DeviceInformationViewController 移除时间链路错误 HUD，补充导航容器关闭时的退出判定；DeviceLightViewController 提供可重新读取的编辑权限。
- GatewayDetailClockCoordinator 增加同设备操作互斥，不改变其时间同步算法和用户主动同步反馈。
- 删除旧的只读准备策略及其单元测试，由新的恢复状态机测试覆盖；更新原有“Information 永不 TimeSet”和“失败必须提示”的契约。
- 新文件已加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 五个 target。
- 未修改 SDK、依赖版本、用户可见文案、资源和布局约束；未执行 Git commit/push。

## 自动化验证

已通过：

- `bash scripts/check_light_information_time.sh`：包括新增 InformationClockRecoveryTests、Gateway/Light 运行契约、时间行契约、Gateway 原手动同步、Fast Add 和 Wi-Fi Proxy Ready 原有行为检查。
- `zsh scripts/check_site_timeset_message_factory.sh`：Site 优先、手机回退、固定偏移及 15 分钟偏移等。
- `zsh scripts/check_site_timeset_call_sites.sh`：已有 TimeSet 调用路径契约。
- `git diff --check`，工程与现有本地化资源格式检查。

新增可控传输测试覆盖四种 Model 绑定组合、首读成功不写、时间未知、读取超时、绑定/写入/回读失败、错误时区、时间超差、只读及能力不足、发送前重新取时间、本地保存失败、重复回调、各阶段页面退出或会话变化、写入权限变化、同设备互斥和旧缓存保护。静态契约另核对完整绑定身份校验、目标 Element、显式 AppKey 和五 target 源码归属。

五品牌最终版本构建均通过，退出码均为 0：SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux。构建使用直接 xcodebuild，Debug、iphoneos、generic/platform=iOS、CODE_SIGNING_ALLOWED=NO。构建仍有现有资源符号重名、AppIntents 元数据等警告，未扩大修改范围处理。

## 验证边界

按用户要求，未安装或启动真机 App，未读取或修改实际 Gateway / Light，未执行设备校时、真机布局或服务器验收，也未使用 Simulator。测试和构建通过不能替代这些验证。

建议设备验收重点：Site 与手机时区不同、时间未知、两个时间 Model 的绑定组合、只读访问、写入成功但回读失败、Gateway 直连与 Light 经 Proxy 路由、连续点击及退出页面。分别核对实际绑定 / TimeSet / TimeGet 顺序、失败无提示、两行显示，以及 Gateway 服务器最终快照。
