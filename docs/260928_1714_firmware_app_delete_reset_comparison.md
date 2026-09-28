# 固件与 App 删除、Mesh Network Reset 行为对比

分析日期：2026-09-28。

本次基于 App、实际映射的 iOS SDK、`sunsmart-fireware` 固件源码作对照，并补充接收函数的离线验证。未修改业务代码、未构建 App 或固件、未连接设备或发送重置命令。

前一份 [App 删除与广播协议分析](260928_1622_device_delete_reset_command_analysis.md) 保留不变；本文补充其此前缺少的固件接收、Mesh 转发、退网和擦除行为。

## 1. 结论

**确实存在重要差异，但不是 CRC32、MAC 字节序或命令字段拼错。当前两端的 `0x08` 逻辑载荷可以匹配，主要问题在广播接收前提、转发范围及结果判定。**

| 发现 | 对实际使用的影响 | 证据性质 |
| --- | --- | --- |
| Lights 删除使用 SIG `ConfigNodeReset`；Force Reset 的 `0x08` 被固件转换成 Sunricher Vendor `48/02` | 两条链路的密钥依赖、响应、延迟和 App 数据库行为不同 | 源码确认 |
| 整网 Vendor 消息目标虽为 `0xFFFF`，但 `send_ttl = 0` | 不能依靠普通 Mesh Relay 覆盖多跳设备，不能把“整网”理解为已保证所有节点都收到 | 固件业务代码与仓库内 Mesh 网络层交叉确认 |
| 单设备 `0x08` 也是发 Vendor 消息给自身，再经本地回环执行 | 不是收到 BLE 广播后直接擦除；仍依赖 Vendor 模型绑定的有效 AppKey 和 Mesh 发送链路 | 源码确认 |
| BLE 接收仅允许 `ADV_NONCONN_IND`，固定在广播数据偏移 5 读取 `0A 78` | App 的 Service UUID 数组本身不能保证这两个空口前提；实际 iOS 包格式仍需抓包 | 接收限制已确认，现场兼容性待验证 |
| 5 秒限流先于 MAC、CRC32 校验 | 其他设备的合法格式重置包、错误 hash 包也会占用接收端限流窗口，抑制随后发给它的有效命令 | 原始接收分支离线验证 |
| 整网成功只依据 App 扫描不到旧 Network ID | 附近设备退网而远端多跳设备仍保留时，也可能显示成功 | 两端源码组合推导，未做现场复现 |
| Force Reset 成功不删除 App 本地 Node | 固件已经退网、App 仍保留旧设备可以同时发生；已知网络同样如此 | App 回调链确认 |

## 2. 版本、入口和证据边界

| 对象 | 本次核对状态 |
| --- | --- |
| App | `fix-delete-devices-260928` 工作树；分支 `fix/delete-devices-260928`；HEAD `3fe9f11b` |
| iOS SDK | `.local-sdk/nordic-sig-mesh-sdk` 实际指向 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`；HEAD `a05b869`；无未提交改动 |
| 固件 | `/Users/maginawin/Developer/SunSmartDev/sunsmart-fireware`；分支 `master`；HEAD `585c45a`；无未提交改动 |
| 当前固件产品选择 | `include/sunsmart_config.h` 启用 `PRODUCT_9033A_MW_V_54L15`；对应入口为 `src/main_9036t.c` |
| 当前产品模型 | 主元素同时包含 Configuration Server 和 Sunricher Vendor Server；初始化调用 `sr_prov_init()` |
| 固件共享实现 | `src/prov.c`、`src/mod_sunricher_srv.c`、`src/sunricher_srv.c`、`src/bsp_sys.c`，均在 CMake 源文件列表中 |
| 仓库中的 Mesh 层证据 | `patches/nrf_3.2.4/zephyr/...`；对 TTL 和回环关键逻辑另核对了 `nrf_2.9.2` 版本，结论一致 |

仓库不是完整 Nordic/Zephyr SDK，没有足以确认当前烧录镜像的构建产物和依赖锁定证据。本次也没有找到可直接对应的本机完整 SDK 环境。因此，下文区分“仓库内代码已确认”与“官方上游参考实现”，不把源码 HEAD、产品宏或版本文件等同于设备当前烧录版本。

标准 Configuration Server、核心 `bt_mesh_reset()`、AppKey 解析和 CRC32 库的缺失部分，参考 Nordic 官方 `sdk-zephyr` 的 `ncs-v3.2.4` 源码；对应关系来自 [nRF Connect SDK v3.2.4 west.yml](https://github.com/nrfconnect/sdk-nrf/blob/v3.2.4/west.yml)。这是补充证据，不能代替现场固件的实际链接版本核对。

## 3. 八种操作的端到端对照

• Lights 删除：需要连接 Proxy，通过 Mesh 逐台发送 ConfigNodeReset；全选也一样。
• Mesh Network Reset 整网重置：不需要连接 Proxy。App 广播给选中的 Proxy，由它向 0xFFFF 发送重置消息。但当前 TTL = 0，不经过中继，只能覆盖它自身及直接
  可达的同网兼容节点，不能保证整个网络都重置。

• Mesh Network Reset 单设备重置：App 直接广播给目标设备自身，使用它的 MAC、地址，dest = 该设备地址，再由设备通过本地回环重置；不是任选一个 Proxy 代发
  给其他设备。

另外，Lights 删除成功会删除 App 本地设备记录；Mesh Network Reset 不会。

### 3.1 Lights 底部删除按钮

| 选择方式 | App 实际发出 | 固件执行入口 | App 本地数据库 |
| --- | --- | --- | --- |
| 单个设备 | 向该节点主单播地址发送 `ConfigNodeReset`，Access opcode `80 49` | Configuration Server 的 Node Reset | 收到匹配的 `80 4A` 后删除 Node，再执行 App 关联清理 |
| 多个不同组设备，非全选 | 按所选节点逐台发送同一命令 | 各设备分别执行标准 Node Reset | 每台按结果处理；可以部分成功、部分失败 |
| 全选整个 Space 的 Lights | 对当前可见灯列表逐台发送；没有整网广播 | 同上 | 同上；有名称筛选时只包含筛选结果，不包含 Sensors 等其他类别 |
| 选择整个组的设备 | 对组内当前可见灯逐台发送；没有组地址重置 | 同上 | 同上；不因此删除 Group 对象 |

这四种选择均没有走固件 `adv_recv()` 的 `0x08` 分支。不能用 Force Reset 的 Vendor TTL、BLE 限流解释正常 Lights 删除的每一种失败。

每台业务请求提交一次，SDK 的可靠消息层会按 ACK/超时重发，不能固定算成一个无线包。正常成功依据是 `ConfigNodeResetStatus`，不是观察设备完成 Flash 擦除。失败一般保留本地 Node；用户选择 `Force Delete` 时仅执行本地删除，不再次向固件发重置。离线设备结果监听比 SDK 可靠消息超时短，迟到 ACK 仍可能删除本地 Node，详见前文第 1.3 节。

### 3.2 Mesh Network Reset 页面

| 场景 | 手机 BLE 命令 | 固件后续动作 | App 判定 | App 本地 Node |
| --- | --- | --- | --- | --- |
| 已知网络，整个网络 | `0x08`；校验选中的代理 A/MAC；目标 `0xFFFF` | 代理发送 Vendor `F0 78 0A 48 02`，TTL 0；代理自身也经回环处理 | 广播结束再等 5 秒，随后 10 秒内未扫描到同 Network ID 即成功 | 不删除 |
| 已知网络，单设备 | `0x08`；校验该设备 A/MAC；目标 A | 设备向自身发送同一 Vendor 消息，经本地回环处理；本地单播不再发往网络 | 广播结束后 10 秒内发现相同 MAC 的未入网设备即成功 | 不删除 |
| 未知网络，整个网络 | 与已知整网相同 | 与已知整网相同 | 相同 | 不删除 |
| 未知网络，单设备 | 与已知单设备相同 | 与已知单设备相同 | 相同 | 不删除 |

“已知/未知”只影响 App 按 Network ID 查找本地 Space 后的显示名称。固件的 `0x08` 载荷里没有 Network ID，也不知道 App 是否保存该网络。

未知网络可以尝试重置，是因为手机向设备发送的是由地址、MAC 和固定 `SR` 字节计算的自定义校验包，不需要由手机为这一步提供该网络的 DeviceKey/AppKey；设备仍必须具备可用的自身 Mesh 配置，才能完成后续 Vendor 发送。

整网操作先选一个可扫描到的代理，再向这个代理发 BLE 命令，没有逐台广播不同 MAC 的补偿循环。单设备操作则要求手机广播可直接到达该设备，不能依靠另一台代理替它通过这个 MAC 校验。

## 4. BLE 广播内容和接收条件

### 4.1 两端匹配的完整逻辑载荷

以下是 App 生成、固件期望读取的 18 字节逻辑内容，不包含系统生成的广播头、手机地址、AD 头、Flags 和链路层 CRC：

```text
0A 78 | 0D | 08 | H0 H1 H2 H3 | M5 M4 M3 M2 M1 M0 | D0 D1 | SUM8 | 00
 CID    LEN  CMD      CRC32            MAC             DST    校验   补齐
```

| 逻辑偏移 | 字段 | App 组成方式 | 固件读取/验证方式 | 比较 |
| --- | --- | --- | --- | --- |
| 0～1 | CID | `CompanyId.bigEndian` → `0A 78` | 直接比较 `0A 78` | 一致 |
| 2 | 长度 | 13，即 `0D` | `0x08` 至少要求 13 字节；允许更长载荷 | App 当前长度兼容 |
| 3 | 命令 | 整网、单设备均为 `08` | 进入同一个 `0x08` 分支 | 一致 |
| 4～7 | CRC32 | 对 `A_LE2 + MAC_REV6 + 53 52` 计算 IEEE CRC32，小端保存 | 用自身当前主单播地址、`_manufacturer[4…9]` 和 `53 52` 分三次更新 CRC32，按小端读取 hash 比较 | 算法和输入一致 |
| 8～13 | MAC | MAC 字符串转 6 字节后反转 | 与蓝牙本机地址字节 `_manufacturer[4…9]` 比较 | 与 App 扫描时反转后展示的 MAC 对应 |
| 14～15 | 目标 | 整网 `FF FF`；单设备 A 的小端字节 | 小端解析为 `ctx.addr` | 一致 |
| 16 | SUM8 | 前 16 字节求和的低 8 位 | CID、长度及长度指示的完整 payload 求和 | 一致 |
| 17 | 补齐 | 为两字节一组 UUID 补 `00` | 当前校验不检查这个尾部补齐字节 | 兼容，但不是固件必需字段 |

这里的 A 在整网时是选中代理的地址，单设备时是目标设备自身地址。整网 A 不在载荷中单独明文发送；它参与 CRC32，而目标字段为 `FFFF`。CRC32 不覆盖目标字段，SUM8 覆盖目标字段。`SR` 是固定校验输入，不是本次用户密码，也没有作为单独字段发出。

固件 CRC32 分段更新的初值为 0；官方实现每次更新前后执行取反，连续分段计算等价于 App 对完整输入一次计算。已用原始上游 CRC32 函数核对示例，得到相同 `0x16A9557E`。[官方 crc32_sw.c](https://github.com/nrfconnect/sdk-zephyr/blob/ncs-v3.2.4/subsys/crc/crc32_sw.c)

### 4.2 完整示例和 Service UUIDs

示例使用虚构地址 `A = 0x1234`、MAC `112233445566`，不是现场设备数据。

```text
CRC 输入：34 12 66 55 44 33 22 11 53 52
CRC 数值：16A9557E；载荷内字节：7E 55 A9 16

整网逻辑载荷：
0A 78 0D 08 7E 55 A9 16 66 55 44 33 22 11 FF FF 8C 00

单设备逻辑载荷：
0A 78 0D 08 7E 55 A9 16 66 55 44 33 22 11 34 12 D4 00
```

App 每两个字节反转后构造一个 `CBUUID`，通过 `CBAdvertisementDataServiceUUIDsKey` 传给 CoreBluetooth：

| 操作 | 九个 16-bit UUID 的 API 表示 |
| --- | --- |
| 整网 | `780A, 080D, 557E, 16A9, 5566, 3344, 1122, FFFF, 008C` |
| 单设备 | `780A, 080D, 557E, 16A9, 5566, 3344, 1122, 1234, 00D4` |

这些 UUID 用于承载命令字节，App 没有为它们建立对应的 GATT Service，也没有通过某个 Characteristic 写入这个重置包。

### 4.3 固件要求的外层包形态

固件首先要求扫描回调的 `adv_type == BT_GAP_ADV_TYPE_ADV_NONCONN_IND`。随后它读取第一个 AD 的长度与类型，但没有按 AD 列表遍历，也没有验证该类型是 Service UUID 列表，而是固定令 `pos = 5`，从整个广播数据的第 5 字节开始检查 CID。

因此下面是一个满足当前解析布局的整网示例，**并非已抓到的 iOS 空口包**：

```text
02 01 06 | 13 03 | 0A 78 0D 08 7E 55 A9 16 66 55 44 33 22 11 FF FF 8C 00
Flags      AD头     固件从广播数据偏移5开始读取的18字节
```

其中 `13` 表示后面有 1 字节 AD Type 加 18 字节 UUID 数据；`03` 为完整 16-bit Service UUID 列表，`02` 为不完整列表。当前固件事实上不检查该 AD Type，只依赖位置与内部校验。

| 广播条件 | 当前固件行为 |
| --- | --- |
| `ADV_NONCONN_IND`，CID 位于偏移 5，长度/校验正确 | 可继续处理 `0x08` |
| 只有 `13 03 + 18 字节载荷`，没有前面的 3 字节字段 | CID 位于偏移 2，被当前固定偏移解析拒绝 |
| 系统增加前置字段、拆分 UUID 数据或改变字段顺序 | 如果 CID 不再位于偏移 5，不能被当前代码正确识别 |
| 同样内容通过 `ADV_IND`、`ADV_SCAN_IND` 或 `SCAN_RSP` 被回调 | 在类型检查处拒绝 |
| Service UUID 位于 iOS 后台 overflow 区域 | 不能据 App 的 UUID 数组推断固件会收到上述原始布局 |

App 虽然传入 `CBAdvertisementDataIsConnectable: false`，但 Apple 的 `startAdvertising` 文档只支持 Local Name 与 Service UUIDs 两类广播输入，并说明系统采用 best-effort 广播、后台 UUID 放入 overflow 区域。因此不能把这项字典赋值当作空口必为 `ADV_NONCONN_IND` 的保证，也不能静态断言所有 iPhone 当前必定失败。实际 PDU 类型、字段顺序、UUID 完整性需在目标 iOS 版本抓包确认。[Apple startAdvertising](https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager/startadvertising(_:))

### 4.4 本流程涉及的 Service

| 阶段 | Service / 通道 | 用途 |
| --- | --- | --- |
| App 寻找已入网设备和整网代理 | Mesh Proxy Service `0x1828`；读取相应 Service Data 与厂商数据 | 识别 Network ID、地址和 MAC |
| App 发出 `0x08` | 上面的九个动态 16-bit Service UUID | 承载私有命令；不是向 `0x1828` 或 `0x1827` 的 GATT 写入 |
| 固件接收 `0x08` | 蓝牙扫描回调 `adv_recv()` | 不建立 GATT 连接；按原始广播数据的固定偏移解析 |
| 固件发送 `48/02` | 已入网 Mesh 的 Vendor Access 消息，使用绑定的 AppKey | Mesh 传输/网络层加密后发送或本地回环；没有另一个叫作 `48/02` 的 BLE Service |
| App 判断整网结果 | Mesh Proxy Service `0x1828` | 扫描是否仍有同 Network ID 设备 |
| App 判断单设备结果 | Mesh Provisioning Service `0x1827` | 扫描同 MAC 的未入网设备 |

固件 `proxy_srv.c`、`pb_gatt_srv.c` 分别提供 Proxy/Provisioning 广播。这里的设备厂商数据用于扫描识别，与手机通过 Service UUIDs 承载的重置包是不同数据结构，不要混用 CID 字节序。

## 5. 收到 `0x08` 后的真实 Mesh 命令

### 5.1 固件处理顺序

在通过广播类型、固定偏移、长度和 SUM8 检查之后：

1. 检查设备已经入网；未入网直接返回。
2. 检查静态计时器，距离上次进入处理不足 5 秒则返回。
3. **立即更新时间，再验证目标 MAC 和 CRC32。**
4. 解析目标地址，构造 Sunricher SET 消息，功能码 `0x48`，子命令 `0x02`。
5. `ctx` 整体清零，只设置 `app_idx = BT_MESH_KEY_UNUSED` 和 `addr = 目标地址`。
6. 包装函数将 `app_idx` 换成 `_sunricher_srv.mod->keys[0]`，调用 `bt_mesh_model_send()`；`adv_recv()` 不检查返回值，也不等待完成回调。

固件另有 `0x05` 分支直接安排恢复出厂，但当前 Mesh Network Reset 整网和单设备均发 `0x08`，不能套用 `0x05` 的行为与时序。

### 5.2 Access PDU 的实际字节

`BT_MESH_SUNRICHER_SETUP_OP_SET` 定义为 `BT_MESH_MODEL_OP_3(0x30, 0x0A78)`。三字节 Vendor opcode 的首字节包含类型位，所以实际 Access PDU 是：

```text
F0 78 0A | 48 | 02
Vendor SET  功能   Leave/Reset
```

即 **`F0 78 0A 48 02`**，不能把宏参数 `0x30` 当成空口 Access opcode 的第一个字节。这里 Company ID 在 Vendor opcode 中编码为 `78 0A`，与私有 BLE 载荷开头人为约定的 `0A 78` 不同。

| 上下文字段 | 当前值/来源 | 含义 |
| --- | --- | --- |
| 目标地址 | 整网 `0xFFFF`；单设备 A | 前者是 All Nodes，后者是自身主单播地址 |
| 源地址 | Sunricher Vendor 模型所在元素 | 当前产品该模型位于主元素 |
| AppKey | Vendor 模型 `keys[0]` | 不是手机提供的 DeviceKey；需要该槽位的绑定和密钥仍可用 |
| TTL | **0** | 来自 `ctx = {0}`，没有设置成默认 TTL 标记 `0xFF` |
| 可靠分段标记 | `send_rel = false` | 这条短消息走非分段发送，没有本函数建立的应用层 ACK 重试 |
| NetKey 选择 | AppKey 所属子网 | 不能仅凭 `ctx.net_idx` 初值 0 推断使用 NetKey Index 0 |

AppKey 到子网的解析参照 [官方 app_keys.c：bt_mesh_keys_resolve](https://github.com/nrfconnect/sdk-zephyr/blob/ncs-v3.2.4/subsys/bluetooth/mesh/app_keys.c)。不同子网或不同 AppKey 绑定的节点，不会仅凭 `FFFF` 就自动具备接收和执行条件。

上述 5 字节是加密前 Access PDU。完整 Mesh 无线包还包含源/目标、序号、IV、网络和应用层加密认证字段，依赖当时网络状态；不能把它与手机的 18 字节 BLE 载荷混称为同一个完整广播包。

### 5.3 整网为什么存在覆盖范围差异

仓库内 `transport.c` 只在 `send_ttl == BT_MESH_TTL_DEFAULT` 时填入默认 TTL；默认标记是 `0xFF`，所以当前初始化为 0 的 TTL 会保持 0。

`net.c` 对 `FFFF` 先安排本地回环，再继续向网络发送。因此接收 BLE 命令的代理自身也会处理 `48/02`。其他直接收到并能解密、分发该 Vendor 消息的节点同样会执行，但网络层 `bt_mesh_net_relay()` 遇到接收 TTL ≤ 1 直接返回，**不会通过普通 Mesh Relay 向更远的多跳设备扩散**。

这不是“发了 FFFF 就等于删掉整个 Network ID”。实际覆盖还受射频可达性、AppKey、Vendor 模型、在线状态及 Friend/Proxy 等部署条件影响；本次没有运行证据用于证明特殊拓扑的覆盖范围。

与 App 整网成功判定组合后，存在明确的误判路径：附近可扫描代理收到并退网，远端必须经中继才能到达的设备未收到；手机随后扫描不到该 Network ID，于是显示成功。该路径由代码推导，尚未现场复现。

### 5.4 单设备为什么也依赖 Mesh 配置

单设备广播使用 A/MAC 通过校验后，又把目标地址设为 A。`net.c` 识别为本地单播时只做回环，不再向无线网络发送这个 Node 的 Vendor 请求。

回环之前仍要经过模型密钥检查与传输层密钥解析。因此“已入网但 Vendor AppKey 未绑定、第一槽位无效或配置损坏”的设备，可能无法通过当前 `0x08` 单设备分支完成重置。固件没有在 Vendor 发送失败时回退到直接恢复出厂，App 也收不到这个发送错误的专用返回。

### 5.5 发送几次：必须分层统计

| 层级 | 当前实现 | 不能推出的结论 |
| --- | --- | --- |
| App 业务操作 | 启动一次 5 秒广播任务，每 0.5 秒开启约 0.1 秒窗口，名义约 9～10 个窗口 | 不能保证 10 个空口包或固件收到 10 次 |
| 固件 BLE `0x08` 处理 | 每台设备共用该分支的 5 秒计时器；每次通过限流与校验只调用一次 Vendor 发送 | 不能将十个窗口计算为十次有效 Mesh 退网请求 |
| 固件应用层重试 | 此处没有检查发送结果、等待 RET 或超时重发的循环 | 失败后不会因此自动重发 |
| Mesh 网络层 | 使用当前 Network Transmit 状态；仓库 Kconfig 默认重传次数 2、间隔 20 ms | 默认对应初发加 2 次重复；运行时可被配置，且单设备本地回环不产生这一组网络广播 |

默认次数对应的广播事件处理可参考 [官方 adv_legacy.c](https://github.com/nrfconnect/sdk-zephyr/blob/ncs-v3.2.4/subsys/bluetooth/mesh/adv_legacy.c) 和 [adv_ext.c](https://github.com/nrfconnect/sdk-zephyr/blob/ncs-v3.2.4/subsys/bluetooth/mesh/adv_ext.c)。它们是底层重复机制，不是“收到重置成功 ACK 后再决定是否重发”。实际射频包数仍需抓包，不能固定乘算为 `10 × 3`。

### 5.6 限流顺序带来的实际影响

只要已入网设备收到外层格式、SUM8 和最小长度都合法的 `0x08`，就会在检查 MAC/hash 前更新时间。因此：

- 发给 A 的广播被附近 B 扫描到，B 即便随后因 MAC 不匹配返回，也已经进入自己的 5 秒限流期。
- 紧接着对 B 发正确广播，B 可能先在限流判断处返回；正确 MAC/CRC32 根本没有机会被验证。
- hash 错误、地址信息过期造成的校验失败同样占用窗口；SUM8 失败则在启动计时器前返回。

这说明限流不是“针对已经成功处理的目标命令去重”。实际 UI 是否触发失败取决于操作间隔、设备扫描和广播时序，不能把这个条件风险描述为每次连续操作必然失败。

## 6. 固件最终是否删除设备、何时退网

### 6.1 Vendor `48/02` 的执行与响应

Vendor Server 收到 SET 后按功能码分发到 `op_prov_leave()`。子命令为 `02` 时，先设置指示灯，再调用 `bsp_sys_factory_reset(3000)`：

```text
收到 48/02
  → 发布恢复出厂事件，安排约 3 秒后的任务
  → 到期：若仍入网则调用 bt_mesh_reset()
  → 再安排约 100 ms 后擦除指定存储区
  → 冷重启
```

`bt_mesh_reset()` 会清除 Mesh 入网状态；当前产品重启流程会恢复 settings、更新地址信息，并启用 Provisioning Bearer。因此正常完成后应重新作为未入网设备出现。Flash 操作本身耗时、工作队列延迟和重新启动时间不包含在“3 秒 + 100 ms”这两个调度参数内。

| 请求目标 | 固件 RET 行为 | App 是否用它判定成功 |
| --- | --- | --- |
| `FFFF` 或普通组地址 | `op_prov_leave()` 不发送 RET | 否 |
| 单播 | 尝试返回 `F3 78 0A 48 02 00`，在真正退网/擦除之前 | 否；当前 Force 单设备场景为发给自身、响应也在本机路径中，不构成手机 BLE ACK |

RET 最后一字节 `00` 表示当前代码安排了操作，不能证明 Flash 已经擦除、重启已经完成。App 的 Force 页面仅观察随后广播，不监听这个 Vendor RET。

### 6.2 普通 `ConfigNodeReset` 的执行与响应

固件主元素具备标准 Configuration Server。官方参考实现收到 `80 49` 后发送无参数 `80 4A`，在发送结束回调中安排 `bt_mesh_reset()`；发送启动回调报告错误时也可能安排 reset。这不是等待手机确认收到了响应。若底层发送 API 直接返回错误、没有进入这些回调，所示 `node_reset()` 只记录错误，不能概括成所有发送失败都会继续 reset。[官方 cfg_srv.c](https://github.com/nrfconnect/sdk-zephyr/blob/ncs-v3.2.4/subsys/bluetooth/mesh/cfg_srv.c)

核心 reset 清除网络/应用密钥与入网状态，并调用模型 reset。仓库中的 Sunricher 模型 reset 回调再调用 `bsp_sys_factory_reset(5000)`，因此普通 SIG 路径还会安排约 5 秒后的设备存储擦除流程。[官方 main.c：bt_mesh_reset](https://github.com/nrfconnect/sdk-zephyr/blob/ncs-v3.2.4/subsys/bluetooth/mesh/main.c)

这与 Vendor 的“先等 3 秒再调用 Mesh reset”顺序不同。Vendor 路径进入 `bt_mesh_reset()` 时也会触发模型回调，但当前正在执行的恢复出厂任务紧接着已安排 100 ms 后擦除和重启，不能机械相加成 `3 秒 + 5 秒 + 100 ms`。

两个重要后果：App 收到 `80 4A` 并删除本地 Node 时，固件后续擦除/重启可能尚未完成；反过来，响应在传输中丢失时，设备可能已经退网而 App 报失败。协议响应、设备最终状态和 App 数据库状态必须分别判断。

### 6.3 “删除”实际对应两个独立存储域

| 存储域 | 普通 Lights 删除 | Force Mesh Network Reset |
| --- | --- | --- |
| 设备自身 Mesh 状态 | 执行到 `bt_mesh_reset()` 后退网 | 只有成功处理 Vendor `48/02` 的设备才退网 |
| 设备自身持久化 | 恢复出厂任务擦除 `storage_partition` 从偏移 0 到“分区大小减 4096”的区域，然后冷重启 | 同一擦除实现 |
| App 本地 Node/属性 | SDK 收到匹配 ACK 后删除，或用户确认 Force Delete 后本地删除 | 不删除，只更新页面扫描数组/网络分组 |
| App Scene/组引用/同步状态 | 进入 `DevicePermanentDeletionContext` 清理与后续同步链 | 未进入该清理链 |

固件并未擦除整颗 Flash，擦除范围明确保留该分区最后 4096 字节。本函数未检查 `flash_area_open()` / `flash_area_erase()` 返回值，也没有把擦除完成结果反馈给手机；因此源码只能确认计划和调用，不能证明每台设备实际持久化清空成功。

## 7. 验证结果及待人工确认事项

### 7.1 已完成的静态与离线核对

提取 `prov.c` 原始 `adv_recv()` 公共解析部分和完整 `0x08` 分支，配合官方原始 CRC32 C 实现编译离线夹具。蓝牙回调类型、时间、入网状态和 Mesh 输出被替身替代；没有启动蓝牙或执行真实擦除。

| 离线用例 | 结果 |
| --- | --- |
| 整网完整示例，预期 Flags/AD 布局 | 进入一次 Vendor 发送；目标 `FFFF`，上下文 TTL 为 0 |
| 单设备完整示例 | 进入一次 Vendor 发送；目标 `1234`，上下文 TTL 为 0 |
| 分三段 CRC32 更新 | 得到 `16A9557E`，与 App 示例一致 |
| 去掉 3 字节前置 Flags 布局 | 固件固定偏移解析拒绝；随后格式正确的包可以处理 |
| 非 `ADV_NONCONN_IND` 类型 | 被拒绝 |
| 错误 MAC，但重新计算出合法 SUM8 | 不发送；0.5 秒后到来的正确包仍被限流，5 秒后才可处理 |
| 错误 CRC32，但 SUM8 合法 | 同样占用限流窗口 |
| 错误 SUM8 | 不占用该分支限流窗口 |
| 相隔 0.5 秒的 10 次接收 | 只进入一次发送；额外在首包 5 秒后注入时可再次进入 |
| 未入网状态 | 不进入 Vendor 发送 |

离线验证只确认接收解析、CRC、分支和计时逻辑，不验证实际 Mesh 加密、AppKey 可用性、本地回环调度、广播发射、Flash 或重启。TTL 中继结论来自网络层源码核对，不是夹具模拟出的射频结果。

临时夹具位于 `/tmp/sunsmart-reset-review-260928/adv_reset_fixture.c`，不属于产品代码或持久测试工程。以上断言全部通过；没有据此宣称 App/固件构建或真机验收通过。

### 7.2 最短现场验证清单

| 验证目标 | 操作与观察 |
| --- | --- |
| iOS 广播兼容性 | 分别抓整网、单设备操作：确认 PDU 类型、CID 偏移、UUID 字节顺序、Flags 与实际广播事件数；前台和后台分别记录 |
| 整网多跳覆盖 | 在明确需经 Relay 到达远端灯的拓扑执行整网重置；分别记录代理、直达灯、远端灯是否退网，不能只看 App 成功提示 |
| 单设备 AppKey 依赖 | 使用可控的测试固件/节点配置，分别验证正常 Vendor 绑定与缺失绑定；观察发送错误和是否进入 `op_prov_leave()` |
| 限流互相影响 | 对同一广播范围内两台设备快速发各自重置指令，记录各机首次进入 `0x08`、MAC/hash 校验与限流时间 |
| 真正的删除完成 | 对比 `80 4A` / `48/02` 到达、入网标志清除、Flash 操作、重启、`1827` 出现及 App 本地 Node 状态 |

这些是待执行项，本次没有自动操作真机。日志若用于后续验证，只需地址、错误码和时间，不需要记录密钥。

## 8. 建议优先处理的方向

本次只分析，以下未实施：

1. **先确认整网重置的覆盖要求并修正 TTL 策略。** 若要求通过 Relay 覆盖多跳，当前固定 0 不符合目标；需要显式选择可中继的 TTL 或默认 TTL 策略，并验证代理自身延迟退网不会截断传播。
2. **抓目标 iOS 版本的真实广播，再对齐外层解析。** 固件应按 AD 结构寻找目标数据，避免固定偏移；可接受的 PDU 类型应由实际兼容要求确定。
3. **把限流与已验证的目标命令关联。** 当前其他目标/错误 hash 也占用窗口，需要调整校验和限流顺序；同时保留合理的重复命令抑制。
4. **明确单设备强制重置在 Mesh 配置损坏时的行为。** 当前依赖 Vendor AppKey；需由产品和固件共同决定是否提供经同等校验后的本机恢复出厂路径，并处理发送失败。
5. **区分“未再发现网络”与“所有设备已重置”。** 已知网络可基于明确设备清单设计核验；未知网络无法凭附近扫描消失证明全部节点退网。是否同步删除 App 本地数据也需单独定义，不能随扫描列表移除隐式执行。

## 9. 源码证据入口

### 9.1 App 与 iOS SDK

| 文件 | 关键入口 |
| --- | --- |
| [DeviceLightsViewController.swift](../SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift) | `deleteNodes()`、选择列表与强制删除 |
| [DeviceMeshNetworkResetHandle.swift](../SunSmart/Main/Device/Reset/Model/DeviceMeshNetworkResetHandle.swift) | 5 秒广播、整网/单设备检查与扫描服务 |
| [DeviceMeshNetworkResetConfiguredController.swift](../SunSmart/Main/Device/Reset/Controller/DeviceMeshNetworkResetConfiguredController.swift) | 已知/未知网络显示、成功后仅删除扫描条目 |
| [BluetoothBroadcaster.swift](../.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Broadcaster/BluetoothBroadcaster.swift) | `BroadcasterType`、`makeUUIDs`、`startAdvertising` |
| [MeshAddDeviceManager.swift](../.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshAddDeviceManager.swift) | `resetNodes` 与扫描字段解析 |

### 9.2 固件仓库

| 文件 | 关键入口 |
| --- | --- |
| [sunsmart_config.h](/Users/maginawin/Developer/SunSmartDev/sunsmart-fireware/include/sunsmart_config.h) / [main_9036t.c](/Users/maginawin/Developer/SunSmartDev/sunsmart-fireware/src/main_9036t.c) | 当前产品宏、模型组成、`sr_prov_init()`、启动后 Provisioning |
| [prov.c](/Users/maginawin/Developer/SunSmartDev/sunsmart-fireware/src/prov.c) | `adv_recv()`、`op_prov_leave()`、`sr_prov_init()`、`sr_prov_update()` |
| [mod_sunricher_srv.c](/Users/maginawin/Developer/SunSmartDev/sunsmart-fireware/src/mod_sunricher_srv.c) | Vendor 组包、首个 AppKey、`bt_mesh_model_send()` |
| [sunricher_srv.h](/Users/maginawin/Developer/SunSmartDev/sunsmart-fireware/include/sunricher_srv.h) / [sunricher_srv.c](/Users/maginawin/Developer/SunSmartDev/sunsmart-fireware/src/sunricher_srv.c) | Vendor opcode、SET 分发、模型 reset 回调 |
| [bsp_sys.c](/Users/maginawin/Developer/SunSmartDev/sunsmart-fireware/src/bsp_sys.c) | `bsp_sys_reset()`、`timeout_factory_reset()`、`timeout_factory_erase()` |
| [transport.c](/Users/maginawin/Developer/SunSmartDev/sunsmart-fireware/patches/nrf_3.2.4/zephyr/subsys/bluetooth/mesh/transport.c) | `bt_mesh_trans_send()` 的 TTL 与重传状态 |
| [net.c](/Users/maginawin/Developer/SunSmartDev/sunsmart-fireware/patches/nrf_3.2.4/zephyr/subsys/bluetooth/mesh/net.c) | `bt_mesh_net_send()` 的本地回环、`bt_mesh_net_relay()` 的 TTL 限制 |
| [access.c](/Users/maginawin/Developer/SunSmartDev/sunsmart-fireware/patches/nrf_3.2.4/zephyr/subsys/bluetooth/mesh/access.c) | 模型密钥/目标匹配和发送前检查 |
| [Kconfig](/Users/maginawin/Developer/SunSmartDev/sunsmart-fireware/patches/nrf_3.2.4/zephyr/subsys/bluetooth/mesh/Kconfig) | Network Transmit 默认次数与间隔 |
| [proxy_srv.c](/Users/maginawin/Developer/SunSmartDev/sunsmart-fireware/patches/nrf_3.2.4/zephyr/subsys/bluetooth/mesh/proxy_srv.c) / [pb_gatt_srv.c](/Users/maginawin/Developer/SunSmartDev/sunsmart-fireware/patches/nrf_3.2.4/zephyr/subsys/bluetooth/mesh/pb_gatt_srv.c) | Proxy/Provisioning Service 广播 |

