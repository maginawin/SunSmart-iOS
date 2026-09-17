# Site Trigger Zone 3A 协议证据与被动日志

日期：2026-09-14。状态：离线核对完成；尚无真实设备协议验收结果，未向测试 Site 发送 Mesh 配置。适用于 `Sep 11 site trigger zone` 的后续人工日志分析。保留当前 Site、Space 及设备配置不变。

## 各项证据能证明什么

| 证据 | 可确认 | 不能确认 |
| --- | --- | --- |
| `get/siteprops` 在 POST 后回读完整目标 | 云端 Site Zone 目标和版本 | 设备已配置、灯具响应 |
| `ConfigNetKeyGet`、`ConfigAppKeyGet`、`ConfigVendorModelAppGet` 的 List/Status | 目标节点上存在相应 Key 索引和 Vendor Model App Bind；错误状态也可记录 | 仅凭相同索引不能证明 Key 材料相同，不能证明设备用哪把 Key 转发 |
| Vendor 邻居 Set 的 `SunricherVendorStatus` RET | 本次收到设备回复及成功/错误码；须与发送步骤、节点、目标指纹关联 | 不能读回邻居、TTL、转发 AppKey，也不能证明断开 App 后联动或断电保持 |
| 本机 Node 缓存的 enabled、relay、neighbors | App 最后一次成功 RET 后缓存的**请求参数** | 设备独立读回；SDK 没有把 TTL、转发 AppKey 放入该缓存 |
| 被动 Sensor Presence / Vendor Trigger 消息 | App 在对应 Mesh 中连接且监听时收到的触发消息与来源地址 | 灯具是否响应；App 或蓝牙断开期间是否曾发生触发 |

协议依据：本地 SDK 的 `SunricherVendorSet.swift` 将转发 AppKey 索引、enabled、relay、TTL、邻居数量和地址编码到邻居 Set；`SunricherVendorGet.swift` 没有对应邻居读回；`SunricherVendorStatus.swift` 对邻居 RET 只解析响应 code、成功标志和错误码；`VendorServerDelegate.swift` 在成功 RET 后直接用原发送请求更新 Node 缓存，并忽略 TTL 与转发 AppKey。已将这四个文件与工程 `Package.resolved` 固定的 `release` 版本 `a6246b1` 逐一比较，内容一致。上述仍是源码结论，需在目标固件上验证实际行为。当前 App 常规 `Node+MessageHandles.swift` 的邻居写入使用 `ttl: 0` 和 `currentApplicationKey.index`，正式 Site 发送器不能沿用这个隐式选择。

后续会话 API 核对发现，SDK 的 `MeshNetworkManager.currentNetworkKey` 在网络无 NetKey 时会生成随机 Key 并保存，`currentApplicationKey` 在网络无 AppKey 时也会新增并保存。因此被动 Debug 日志不调用这两个 getter 来“查询”实际 Key；Site Zone 已有的连接状态读取先检查 NetKey 清单非空，空清单直接返回不可用。当前 `plan-space` 只记录解析自 Space 清单的**传输候选**，并不宣称它就是运行中使用的 AppKey。真正的会话 Key 与 Vendor Model Bind 核验留在受控 3A/3C 流程。

## 本次日志改动

Site Trigger Zone 页面保持可见、App 前台且收到同一 Site Mesh 消息时，`[SiteZoneSync][passive-trigger]` 现在记录 Presence、Vendor Trigger，以及邻近照明 enabled/relay/neighbor RET 的 code、成功标志和错误码；同时记录活跃 Space、连接状态。日志只在 Debug 编译中存在，不发送命令、不记录 Key 材料。收到 RET 时 `deviceEvidence=unverified` 仍是正确结果：这个被动监听没有已冻结的发送任务、请求与目标指纹，不能将任意 RET 归到当前 Zone。

页面可见且在前台时，`[SiteZoneSync][mesh-session]` 另记录 Site Zone 所用 Space 连接对象的 `idle/connecting/connected/failed` 变化及该时刻是否仍匹配并连接目标 Space。它有助于解释“监听已启动但没有触发消息”；这只是 App 会话状态，不是设备触发或传输 AppKey 的证明。App 退出或后台期间无法产生连续的手机日志。

`phase=active` 表示页面监听已注册，**不等于**蓝牙已连接；须看 `meshConnected`。没有 `event` 行只表示监听窗口内未收到该类消息，不能推断设备没有触发。断开 App、关闭蓝牙或 App 进入后台后，iPhone 无法采集 Mesh 消息；这解释了用户触发设备时手机界面没有变化的可能性，但不能单独判断设备是否已联动。日后若用户自行测试，应结合灯具现场观察和连接状态、时间点、Space/地址、对应日志一起判读。

## 后续放行边界

3A 仍缺独立且可回退的 Space 1/2 现场范围、旧 Group Path 行为基线、设备 Key/Bind 实测、固件对邻居 Set/RET 的实际响应、双向响应与断线/断电保持、故障回退。原跨 Space 3 Zone 与新两 Space 成员完全重叠，不能用重叠区域内的单次触发证明新 Zone 配置成功。用户已明确暂缓配合现场测试；在其自行提供可判读日志和观察结果前，3C 发送器与正式同步入口继续关闭。
