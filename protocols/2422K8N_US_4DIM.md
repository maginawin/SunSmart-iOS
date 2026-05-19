# PRODUCT_2422K8N_US_4DIM APP对接文档

> 文档状态：基于 `LPN` 分支当前代码（`include/sunsmart_config.h:1311-1328`、`config/2422K8N_US_4DIM/prj.conf`、`src/main_lpn.c`、`src/mod_lpn_*.c`、`src/mod_dfu_srv.c`、`src/bsp_button_irq.c`、`src/bsp_battery.c`）整理，方案为 `8-element（主元素吸收按键 0 + DFU SRV 与按键 1 共用 Element 2） + 每按键 5 Client Model（含 Lightness） + 0x4C 动作 type 0~8（含 LIGHTNESS_SET） + SIG 标准 Mesh DFU 通道`。
>
> ⚠ **2026-04-25 同步**：产品已正式改名，**Product ID 由旧值 `0x2601` 调整为 `0x2602`**、**GATT/广播设备名由旧值 `2422K8N_US_4DIM` 调整为 `2422K8NUSD`**。APP 端扫描匹配、白名单、产品识别表均需同步更新；旧 `0x2601` / `2422K8N_US_4DIM` 已弃用，不再使用。
>
> ⚠ **2026-05-09 v1.2.12 同步**：**Product ID 再次调整 `0x2602` → `0x2A02`**（小端字节序 `02 2A`）。同时新增同构兄弟产品 **`PRODUCT_2422K8N_US_4SC`（PID `0x2A01`）**——硬件/软件完全一致，仅 PID 不同，APP 需在产品识别表里同时登记 4DIM/4SC 两个 PID。新增公共特性宏 `PRODUCT_HAS_LOW_POWER`（4DIM/4SC 共用 LPN 行为）；预留 `PRODUCT_HAS_NFC_TAG`（FM11NT083C NFC 双界面 tag，当前调试期注释关闭）。`MAX_BUTTON_HANDLERS` 由 5 上调到 6（留 1 buffer 给 NFC selftest combo handler）。`products` hash 已回填 `5372592f`，分类 `Battery`。
>
> ⚠ **2026-04-28 同步**：元素结构从 9 → 8（按键 0 上移到主元素，DFU SRV 加入 Element 2 与按键 1 共用），与 9035AJ_PIR_V_54 的 DFU SRV 位置（Element 2）对齐。**按键源地址全部前移 1**：Key1 现在 = `primary + 0`（主元素），Key2~Key8 = `primary + 1`~`primary + 7`。详见 §3 / §3.1。

## 1. 产品一句话说明

`PRODUCT_2422K8N_US_4DIM` 是一个 **BLE Mesh 8 键低功耗遥控器（LPN Remote Controller）**：

- 本机不驱动本地灯负载
- 通过标准 SIG Client Model 向网络内目标灯具或组地址发送控制命令
- 通过 Sunricher Vendor Model 提供按键映射配置、设备识别、OTA 等能力
- 设备是 LPN 节点，正常运行时以低功耗轮询方式接入 Mesh 网络

## 2. 识别信息

### 2.1 基本识别

| 项 | 值 | 来源 |
| --- | --- | --- |
| 产品宏 | `PRODUCT_2422K8N_US_4DIM` | `include/sunsmart_config.h:110` |
| **Product ID** | **`0x2A02`**（小端 `02 2A`） | `include/sunsmart_config.h:1312` |
| **GATT/广播设备名** | **`2422K8NUSD`** | `config/2422K8N_US_4DIM/prj.conf:6`（`CONFIG_BT_DEVICE_NAME`） |
| Bootloader Banner | `2422K8N_US_4DIM` | `prj.conf:2`（仅启动 LOG，**APP 不应据此识别设备**） |
| Company ID | `0x0A78` | 厂商分配 |
| 产品分类 | `Battery` | `products` 文件 |
| Element 数量 | `8` | `main_lpn.c` |
| `products` 中登记 hash | `5372592f` | `products` 第 68 行 |
| 同构兄弟产品 | `PRODUCT_2422K8N_US_4SC`（PID `0x2A01`） | 硬件/软件一致，仅 PID 不同 |

说明：`products` 里的 composition hash 仍是占位值，表示发布元数据还没有最终收口。

> ⚠ APP 不要把启动 banner（`2422K8N_US_4DIM`）当成 GATT 设备名匹配；GATT 与广播里实际广播的是 **`2422K8NUSD`**。

### 2.2 Manufacturer Data 结构

设备初始化和 `sr_prov_update()` 后，广播里会维护 14 字节 manufacturer data：

| 偏移 | 长度 | 含义 |
| --- | --- | --- |
| 0~1 | 2 | Company ID，小端，当前为 `0x0A78` |
| 2~3 | 2 | **Product ID，小端，当前为 `0x2A02`**（即字节序 `02 2A`） |
| 4~9 | 6 | 设备蓝牙 MAC |
| 10 | 1 | 事件标志位；本产品当前可视为保留 |
| 11 | 1 | `custom_id` |
| 12~13 | 2 | 主元素地址，小端 |

### 2.3 UUID

- Provisioning UUID 来自 `hwinfo_get_device_id()`
- 不足 16 字节会按代码规则补齐
- APP 不应假设 UUID 和 MAC 可以直接互相推导

## 3. Composition 与模型能力

`main_lpn.c` 当前采用 8-element 结构（按键 0 上移到主元素 + DFU SRV 加在 Element 2）：

| Element | 模型 | 用途 |
|---------|------|------|
| 1 | Config Server | Mesh 基础配置 |
| 1 | Health Server | 健康状态 |
| 1 | **Generic Battery Server (SIG 0x100C)** | 对外暴露设备电量 / 电池状态 |
| 1 | OnOff Client / Level Client / Light Ctrl Client / Scene Client / **Lightness Client** | **Key1（协议 index 0）对应端点** |
| 1 | Sunricher Vendor Setup Server | 私有配置、Vendor OTA、设备管理 |
| 2 | OnOff Client / Level Client / Light Ctrl Client / Scene Client / **Lightness Client** | Key2（协议 index 1）对应端点 |
| 2 | **BT_MESH_MODEL_DFU_SRV (含 BLOB Server)** | **SIG 标准 Mesh DFU 升级入口（与 9035AJ_PIR_V_54 同位置）** |
| 3 | OnOff Client / Level Client / Light Ctrl Client / Scene Client / **Lightness Client** | Key3（协议 index 2）对应端点 |
| 4 | OnOff Client / Level Client / Light Ctrl Client / Scene Client / **Lightness Client** | Key4（协议 index 3）对应端点 |
| 5 | OnOff Client / Level Client / Light Ctrl Client / Scene Client / **Lightness Client** | Key5（协议 index 4）对应端点 |
| 6 | OnOff Client / Level Client / Light Ctrl Client / Scene Client / **Lightness Client** | Key6（协议 index 5）对应端点 |
| 7 | OnOff Client / Level Client / Light Ctrl Client / Scene Client / **Lightness Client** | Key7（协议 index 6）对应端点 |
| 8 | OnOff Client / Level Client / Light Ctrl Client / Scene Client / **Lightness Client** | Key8（协议 index 7）对应端点 |

### 3.1 按键与 Element 映射

| 按键 | 协议索引 | Element idx | Mesh 源地址 |
| --- | --- | --- | --- |
| Key1 | 0 | 0（主元素） | `primary + 0` |
| Key2 | 1 | 1 | `primary + 1` |
| Key3 | 2 | 2 | `primary + 2` |
| Key4 | 3 | 3 | `primary + 3` |
| Key5 | 4 | 4 | `primary + 4` |
| Key6 | 5 | 5 | `primary + 5` |
| Key7 | 6 | 6 | `primary + 6` |
| Key8 | 7 | 7 | `primary + 7` |

结论：

- 按键级标准模型消息现在具备独立源地址
- **Key1 与主元素共享 element idx 0，源地址等于 primary**——APP 端不能再假设"按键 i 在 primary + i + 1"
- APP 应通过 Composition Data Get 动态发现按键 element 位置，避免硬编码偏移
- Vendor 私有协议仍然挂在主元素 `Element 1`
- SIG 标准 Mesh DFU 入口在 **`Element 2 (idx 1)`**，与 Key2 共享 element，APP 端 SIG DFU 客户端流程与 `PRODUCT_9035AJ_PIR_V_54` 完全一致

## 4. APP 必须完成的 Mesh 配置

建议联调顺序：

1. 对设备完成标准 Mesh provisioning
2. 给 `Element 1` 的 Vendor Model 绑定 AppKey（用于 `0x4C` 配置 / `0x36` OTA 等私有协议通道）
3. （可选）给 `Element 1` 的 Generic Battery Server 绑定 AppKey，用于 APP 主动 GET 电量
4. 给 `Element 2~8` 的对应 Client Model 绑定 AppKey
5. 读取能力信息和当前按键配置
6. 按业务需求逐键写入 `button + trigger` 动作映射（不需要的可以不写，默认静默）
7. 如需 OTA 或高频配置，提示用户双击任意键打开通信窗口

至少要覆盖的绑定关系：

- `Element 1 / Vendor Model`：用于 `0x4C`、`0x48`、`0x36` 等私有协议
- `Element 1 / Generic Battery Server`：用于电量查询
- `Element 1 / Health Server`：用于接收设备主动上报的故障（详见 §10）；**额外需要下发 `Config Model Publication Set`**，否则故障在空中不可见
- `Element 2~8 / OnOff Client`：用于开关动作
- `Element 2~8 / Level Client`：用于亮度 step / move
- `Element 2~8 / Scene Client`：用于场景召回
- `Element 2~8 / Light Ctrl Client`：仅当要使用 `light_ctrl_onoff` 时绑定
- `Element 2~8 / Lightness Client`：仅当要使用 `lightness_set` 绝对亮度时绑定

## 5. 低功耗与通信约束

### 5.1 Mesh 运行模式

该产品启用了 LPN：

- `CONFIG_BT_MESH_LOW_POWER=y`
- `CONFIG_BT_MESH_LPN_AUTO=n`（由固件状态机手动开关）
- `CONFIG_BT_MESH_LPN_POLL_TIMEOUT=108000`（Friend 订阅存续 ~3 h，单位 100 ms）
- `CONFIG_BT_MESH_LPN_INIT_POLL_TIMEOUT=300`（首次 Init Poll 超时 30 s）
- 轮询节奏由 SDK 内部管理（没有固定的业务层轮询周期常量）
- `Relay`、`Friend` 编译时关闭
- **`GATT Proxy` 编译时启用 + 默认 runtime 关闭**（**动态切换**：通信窗口期开，平时关，详见 §5.4）

结论：

- 设备自身是 **LPN 节点**
- **通信窗口期可作为 Proxy 节点 APP 直连**；其它时段不广播 Proxy Service
- 对该设备的 Vendor 配置和 OTA：**优先方式是 APP 直连本机 GATT Proxy**（窗口期）；备选方式是通过其它 Proxy 节点中转

### 5.4 GATT Proxy 动态切换（**重要**）

| 设备状态 | GATT Proxy (0x1828) | PB-GATT (0x1827) | APP 是否能直连 |
|---|---|---|---|
| `LPN_RUN`（已配网正常运行） | OFF | OFF | ❌ |
| **上电激活模式 60s**（`WAIT_START`，未配网，v0.2.6+） | N/A | **ON** | ✅ 用 PB-GATT 配网，等价 Key2+Key7 长按 |
| **上电激活模式 60s**（`WAIT_START`，已配网，v0.2.6+） | **ON** | OFF | ✅ **用 GATT Proxy 直连** |
| `WAIT_START`（Key2+Key7 60s combo 窗口，未配网） | N/A | **ON** | ✅ 用 PB-GATT 配网 |
| `WAIT_START`（Key2+Key7 60s combo 窗口，已配网） | **ON** | OFF | ✅ **用 GATT Proxy 直连** |
| **`WAIT_RESUME`**（**配网完成 60s Config 宽限期**） | **ON** | OFF | ✅ **用 GATT Proxy 直连** |
| `WAIT_RESUME`（PROV_SLEEP 按键唤醒 1s） | OFF（按键 wake 路径不开 Proxy，避免 -ENOTCONN） | OFF | ❌ |
| `WAIT_RESUME`（OTA Stop / 60s post-prov 续期） | **ON** | OFF | ✅ |
| `ACTIVE`（OTA 升级中） | **ON** | OFF | ✅ |
| `PROV_SLEEP` / `UNPROV_SLEEP`（深睡） | OFF | OFF | ❌ |

**APP 流程关键变化**（vs 旧版）：

- 配完 LPN 后**不需要重连到别的 Proxy 节点**——直接保持原 GATT 连接（从 PB-GATT 无缝切到 Proxy），继续发 Config Add AppKey / Bind / ...
- 单 LPN 设备 + 手机 APP 也能完整工作，**不需要别的 Proxy 节点存在**
- OTA 走 APP 直连 GATT，速度比"经第三方 Proxy 节点 ADV 转发"快 2~3 倍
- 60s 窗口结束设备自动关 Proxy，APP GATT 连接会被踢

⚠ **APP 注意事项**：

- LPN_RUN 期间扫描不到 GATT Proxy → 这是设计如此，不是设备掉线
- 若想发 Config 或 OTA，引导用户长按 Key2+Key7 3s 打开窗口，等设备开始广播 Proxy 后再连接

### 5.2 配网窗口与通信窗口

#### 未入网时

**上电分流（v0.2.6 修订）：**

- **正常上电**（拔插电池 / 首次上电 / 软重启 / POR / SREQ）→ 自动进入"激活模式"
  - 视觉行为与 Key2+Key7 长按 3s 一致，**直接打开 60 秒通信窗口**（PB-GATT 开，APP 可扫到并配网）
  - ⚠ **与 Key2+Key7 的区别**：上电激活模式**不允许 Vendor SET 续期**（固定 60s 到点就睡）。如果 APP 需要在窗口里发大量配置（44 个 model bind 等），可能撞 60s 上限——这种场景应该引导用户**显式按 Key2+Key7 长按 3s** 走 combo 路径，那个路径的 Vendor SET 会续期到 30s 让窗口可远超 60s
  - LED 反馈：**3 秒常亮 + 之后每 3 秒短闪一次**，持续整个 60s 激活期，向用户/APP 提示设备处于可配网状态
  - 60s 期间 APP 应抓紧完成 PB-GATT 配网；超时无操作 → **立即**关 PB-GATT + 挂起 mesh，进入永久休眠（v0.2.6 之前还有 10s 多余尾巴，已删除，详见工程文档 §10.1.11）
- **WDT 复位**（固件 crash / 异常恢复）→ 直接进永久休眠，**不开 PB-GATT、不亮 LED**
  - 设计意图：WDT 触发说明前次有异常，最稳妥就是不主动做事，避免反复 WDT → 反复打开高功耗窗口的恶性循环
  - 用户从外观上看"刷完固件啥都没有"是正常现象，需要拔插电池触发一次 POR 才会进激活模式
- **休眠后的唯一唤醒方式：`Key2+Key7 长按 3 秒`** → 打开 60 秒通信窗口（同时开 PB-GATT）
- ⚠ **单键短按／长按在未配网态下被忽略**（不开 PB-GATT、不唤醒 mesh），仅 LED 慢闪 3 次给用户反馈

⚠ APP 侧的含义：

1. 上电 60s 内 APP 必须完成扫描和配网；超时设备进永久休眠后必须引导用户**长按 Key2+Key7 三秒**才能再次配网
2. 用户按错单键设备不响应 → APP 端必须明确告诉用户**长按 Key2+Key7 三秒**，不能让用户随便按
3. 这是为了避免误触发耗电（口袋里碰到按键不会让设备醒来）+ 强制用户表达明确配网意图
4. **首次烧录新固件时**，RESETREAS 寄存器里可能残留旧 WDT bit，第一次上电会跑 WDT 路径（无 PB-GATT、无 LED）；**第二次上电起**才进入正常激活模式行为。生产线测试要给设备至少两次上电机会

#### 配网刚完成（**Config 宽限期**）

provisioning 协议结束的瞬间，设备**自动进入 60 秒通信窗口**（不进 LPN，scan 持续打开，GATT Proxy 开），用于 APP 一次性发完所有 Config 阶段的消息：

> ⚠ **60 秒"无活动"超时**：APP 在 60s 内发任意 Config / Vendor 消息都会触发**自动续期到 30s**（`max(remaining, 30s)` 保护逻辑——剩余时间充足时不缩短）。所以只要 APP 持续发，窗口理论上无限延长；APP 完全停发 30s 后窗口才结束。

| APP 推荐发送顺序 | 消息 |
|---|---|
| 1 | `Config Add AppKey` |
| 2 | `Config Model App Bind` × 多个 model（Vendor / Health / Battery / Element 2~8 OnOff Cli / Lvl Cli / LightCtrl Cli / Scene Cli / Lightness Cli） |
| 3 | `Config Model Subscription Add`（如需组控） |
| 4 | `Config Model Publication Set` for Health Server（详见 §10.2） |
| 5 | `Vendor SET 0x4C 0x00` 写每键动作配置（可选） |

⚠ **必须在 60s 内发完**，超时设备会自动进 LPN 深睡。如果 Config 没发完，下次只能：
- 让用户按 `Key2+Key7 长按 3s` 重新开 60s 窗口
- 或等设备进入 LPN_RUN 后让 Friend 缓存 Config 消息（速度慢，依赖 Friend 节点）

⚠ **不要在配网完成的瞬间立刻退出 APP** —— Config 流程没走完就退出会导致设备配置不完整，下次需要重新打开通信窗口补发。

如果 60s 内 APP 还按物理键测试，定时器会被缩短到 **1 秒**（v0.2.6 由 10s 缩短）。

#### 已入网时

设备进入 `LPN_RUN`，任一按键即可发业务指令（通过 Friend 代发）。需要长时间高交互（OTA、连续配置、查询）时，**长按 `Key2+Key7` 3 秒**打开 60 秒通信窗口（多击已取消，双击不再产生通信窗口）。该组合在已入网、未入网两种状态都可用。

#### 60 秒窗口内的行为规则

1. **窗口内已配网 + 用户按普通键** → 窗口自动缩短为 `1 秒`（v0.2.6 由 10s 缩短），1 秒后休眠（避免用户完成操作后还白等）
2. **窗口内正在配网（prov_link_active）到 60 秒** → 不立即休眠，等 prov link 关闭（完成或失败），关闭后再加 `10 秒尾巴` 才休眠
3. **窗口内完全无活动到 60 秒** → 正常结束：已配网回 `LPN_RUN`、未配网回永久休眠
4. **APP 在 combo 窗口期发 Vendor SET（如 `0x4C` 按键配置）** → 自动续期 30 秒（**v0.2.6 新增**），允许 APP 大批量配置不撞 60s 上限。详见 §5.5

### 5.3 打开通信窗口的唯一途径

- 多击（双击/三击/五击）已取消，因此 `Key2+Key7 长按 3s` 组合是**唯一**打开 60s 通信窗口的按键方式
- `Key2+Key7` 组合不走 `0x4C` 业务映射，APP 不能配置或禁用

### 5.5 Vendor SET 续期机制（v0.2.6 新增）

**仅 Key2+Key7 长按 3s 进入的 60s combo 窗口才允许续期**。其他场景（按键 wake、配网完成 60s post-prov、OTA 窗口）**不续期**。

**续期规则**：

- APP 通过 Vendor SET（任何 opcode，含 0x4C 按键配置）触发
- timer 剩余 < 30s 才续到 30s（剩余 ≥ 30s 不动，保护初始 60s 窗口不被缩短）
- 1 秒合并保护：1s 内多条 SET 只续一次

**APP 推荐工作流**（批量配置 KEY1-KEY8）：

```text
1. APP 引导用户长按 Key2+Key7 3 秒
   → 设备打开 60s combo 窗口
   → log: combo comm window opened (60000 ms, config_traffic extension enabled)
   
2. APP 连续发 0x4C 按键配置（耗时 1-2 分钟）
   → 每条 SET 触发续期，timer 剩余 < 30s 时续到 30s
   → 持续配置无限制
   → log: [CFG-EXT] config traffic, extend window to 30000 ms (was XXX ms)

3. APP 配完静默 ≥ 30s
   → timer 自然过期
   → 设备回 LPN_RUN 节能
   → log: ota idle timeout, resume lpn
```

**不续期的常见误区**：

- ❌ 配网完成后 60s post-prov 窗口期发 0x4C → **不续期**（不是 combo 来源）
- ❌ 按键 wake 后 1s 短窗口期发 0x4C → **不续期**
- ❌ OTA 通信窗口期发 0x4C → **config_traffic 不续期**（但 OTA 自己有 60s 续期机制）

**结论**：APP 任何**大批量** 0x4C 操作必须先引导用户长按 Key2+Key7。

## 6. 物理按键与触发

### 6.1 按键定义

| 按键序号 | 协议索引 | 别名 (DTS) |
|---------|----------|-----------|
| Key1 | 0 | `button0` |
| Key2 | 1 | `button1` |
| Key3 | 2 | `button2` |
| Key4 | 3 | `button3` |
| Key5 | 4 | `button4` |
| Key6 | 5 | `button5` |
| Key7 | 6 | `button6` |
| Key8 | 7 | `button7` |

8 颗主键行为完全对称、均可由 APP 通过 `0x4C SET` 任意配置。  
另外硬件还有一颗 `SW1 fault` (`button8`，协议索引 8)，固件层只打 LOG，**不接受 APP 配置**，APP 不需关心。

### 6.2 触发判定

当前实现以 `bsp_button_irq.c` 为准：

- 去抖：`30 ms`
- `PRESS` 起点：`800 ms`
- `LONG_PRESS` 起点：`3000 ms`

`0x4C 0x01` GET 能力返回 `trigger_count = 5`。支持的 trigger：

| trigger 值 | 名称 | 说明 |
| --- | --- | --- |
| 0 | click | 单击（按下并松开，无多击合并延迟） |
| 1 | long_press | 按下达到 3s |
| 2 | long_release | ⚠ **v0.2.8 起合并到 `press_release`**：协议层仍可写入此 trigger（保护已下发的旧配置），但运行时**不会单独触发**——任何 ≥800ms 松开都改走 `press_release` (trigger=4) 配置。新接入 APP 直接配 trigger=4 即可 |
| 3 | press | 按下达到 800ms |
| 4 | press_release | 800ms 后松开 |

⚠ **多击（双击/三击/五击）已全部取消**：固件不再产生 `double_click / triple_click / five_click` 事件，APP `0x4C 0x00 SET` 写 trigger ≥ 5 会返回 `err=2`（字段非法）。老固件可能在 NVS 里留下 trigger=5/6/7 的配置条目，这些条目不会被清理，也**永远不会触发**（无害）。

### 6.3 组合键触发（本地保留，不通过 `0x4C` 配置）

固件识别以下两组组合键长按（3s 阈值，与单键 `LONG_PRESS` 同时间）：

| 组合 | 按键索引 | 动作 | 条件 |
| --- | --- | --- | --- |
| `Key2 + Key7` | 1 + 6 | 打开 60 秒通信窗口（见 §5.2） | 已入网、未入网均生效 |
| `Key1 + Key8` | 0 + 7 | **恢复出厂**（LED 闪烁 + 3.5s 后清 NVS 重启）；LED 优先级最高，不受 §8.3 enable 控制 | 不限状态，包括未入网也会触发 |
| `Key2 + Key7` | 1 + 6 | 60s 通信窗口 + LED 常亮 3s（受 §8.3 enable 控制） | 已入网/未入网均生效 |

这两组组合是硬编码本地行为，**APP 不能通过 `0x4C` 禁用或重新配置**。其他组合（如 `COMBO_CLICK` / 其他两键长按）固件能识别但未绑定任何动作。

## 7. 默认行为

### 7.1 出厂默认键表

当前代码不再给 8 个按键预置默认组控/场景映射：

- 所有 `button + trigger` 默认都是 `disabled`
- 保留如下本地动作（硬编码，**不经 `0x4C` 协议，APP 不能改**）：
  - `Key1 + Key8 长按 3s`（组合） → 本地恢复出厂
  - `Key2 + Key7 长按 3s`（组合） → 打开 60s 通信窗口（已入网/未入网均生效）
  - 任一按键卡住 ≥ 60 秒 → `Health Current Status` 上报（详见 §10）

这意味着：

- 未经过 APP 写入 `0x4C` 配置时，按键按下**不会产生任何 Mesh 业务报文**
- 标准 Client 模型不会默认向任何组地址发消息
- 设备也**不发送任何 Vendor 私有事件**
- 但 Health Server 故障（按键卡住）仍会按 APP 下发的 Publication 参数主动上报

### 7.2 未配置触发的行为

当前版本规则：**`type == DISABLED` 即静默**。

- 出厂默认未配置的按键 → 按下无任何网络效应
- APP 显式 SET 成 `disabled` 的按键 → 按下无任何网络效应
- 二者在网络侧**完全等价**

> 历史说明：早期版本提供过"未配置触发 → 主元素 Vendor 发 `EVENT 0x35` 到组地址 `0xD000`"的默认回退事件，由编译宏 `LPN_RC_ENABLE_DEFAULT_VENDOR_FALLBACK` 控制。**当前版本已完全移除该机制**：宏、`LPN_RC_DEFAULT_VENDOR_ADDR` 常量、`EVENT 0x35` 默认事件均不存在。如有 APP 侧针对 `0xD000` 的订阅/监听逻辑，请清理。

## 8. 按键配置私有协议

### 8.1 Vendor Model 基本信息

- Company ID：`0x0A78`
- Model ID：`0x0001`
- Vendor SET opcode：`0x30`
- Vendor GET opcode：`0x31`
- Vendor RET opcode：`0x33`
- Vendor EVENT opcode：`0x35`
- Vendor OTA opcode：`0x36`

### 8.2 按键配置子 opcode：`0x4C`

#### 8.2.1 GET 能力

请求：

```text
Vendor GET 0x4C 0x01
```

返回：

```text
Vendor RET 0x4C 0x01 0x00 <button_count> <trigger_count> <config_version>
```

当前返回：

- `button_count = 8`
- `trigger_count = 5`（多击已取消，仅 click/long_press/long_release/press/press_release）；⚠ v0.2.8 起 `long_release` 实际不再单独触发，所有 ≥800ms 松开统一走 `press_release`，详见上表
- `config_version = 2`

#### 8.2.2 GET 单项配置

请求：

```text
Vendor GET 0x4C 0x00 <button> <trigger>
```

成功返回：

```text
Vendor RET 0x4C 0x00 0x00 <button> <trigger> <type> <value> <level_le16> <scene_id_le16> <addr_le16> <app_idx_le16> <ttl>
```

说明：

- `type=0` 表示 `disabled`，按下后设备静默不发任何 Mesh 报文
- 当前 GET 返回的是动作值，不返回"是否曾被 APP 配置"的内部标志
- "默认未配置"与"APP 显式 disabled"在网络行为上完全等价

#### 8.2.3 SET 单项配置

请求：

```text
Vendor SET 0x4C 0x00 <button> <trigger> <type> <value> <level_le16> <scene_id_le16> <addr_le16> <app_idx_le16> <ttl>
```

成功返回：

```text
Vendor RET 0x4C 0x00 0x00
```

设备收到有效 SET 后会把该项落 NVS 持久化。`type=0/disabled` 为合法值，写入后该按键按下静默。

**字段含义说明**：

| 字段 | 类型 | 含义 |
|---|---|---|
| `button` | u8 | 按键索引 0..7（对应 Key1..Key8） |
| `trigger` | u8 | 触发方式 0..4（CLICK / LONG_PRESS / LONG_RELEASE / PRESS / PRESS_RELEASE）；⚠ trigger=2 仅协议保留，运行时不触发，统一走 trigger=4 |
| `type` | u8 | 动作类型 0x00..0x08（详见 8.2.3 type 表） |
| `value` | u8 | OnOff / LightCtrl OnOff 时的目标 0/1；其它 type 忽略 |
| `level` | i16 LE | LEVEL_DELTA / LEVEL_MOVE 的 delta；LIGHTNESS_SET 时按 u16 解读为绝对亮度 |
| `scene_id` | u16 LE | SCENE_RECALL 场景号；其它 type 忽略 |
| `addr` | u16 LE | 目标 Mesh 地址（单播 / 组播 / 虚拟），`0x0000` 表示未配置 |
| `app_idx` | u16 LE | **AppKey Index**（**不是** NetKey Index）；`0xFFFF` 表示未配置 |
| `ttl` | u8 | Mesh 消息 TTL（0..127）；`0xFF` = 用默认 TTL |

⚠ **`app_idx` 关键说明**：

- 这是 **AppKey 索引**——APP/网关向设备 Add AppKey 时拿到的 index（一般是 0、1、2…）
- **不是** NetKey Index；BLE Mesh 模型层消息（OnOff / Lvl / Scene / Lightness / LightCtrl Set）必须用 AppKey 加密，固件会按 `app_idx` 自动反查所属 NetKey
- 必须填**已经给"对应按键 element + 对应 Client Model"Bind 过**的 AppKey 的 index，否则设备发包时 Mesh 协议栈拒绝（按键按下无任何报文上行）
- 推荐：联调初期统一用主元素 Vendor Model 那把 AppKey 的 index，按键 element 全部 bind 同一把

`type` 全量枚举（详见 Vendor 协议主文档 [0x4C](d:\claude_code\sunricher_protocol_vendor\team-docs\sunricher_protocol_vendor.md)）：

| type | 名称 | addr/app_idx | 使用字段 | 行为 |
|---|---|---|---|---|
| 0x00 | DISABLED | 否 | — | 按下静默，不发任何 Mesh 报文 |
| 0x01 | ONOFF_TOGGLE | 是 | `value`（初始 shadow） | 翻转 OnOff |
| 0x02 | ONOFF_SET | 是 | `value`（0/1） | 固定 OnOff |
| 0x03 | LEVEL_DELTA | 是 | `level`（i16） | Generic Level Delta Set（transition 200 ms） |
| 0x04 | LEVEL_MOVE | 是 | `level`（i16 速率） | Generic Level Move Set（transition 1000 ms） |
| 0x05 | SCENE_RECALL | 是 | `scene_id` | Scene Recall（transition 500 ms） |
| 0x06 | LIGHT_CTRL_ONOFF | 是 | `value`（0/1） | Light LC Client OnOff |
| 0x07 | FACTORY_RESET | 否 | — | 本地工厂复位（LED 提示 + 3.5 s 后重启），不发 Mesh |
| **0x08** | **LIGHTNESS_SET** | **是** | **`level` 按 u16 解读（0x0000..0xFFFF 绝对亮度）** | **Lightness Client Light Set，transition 500 ms** |

⚠ `type` 需要 addr/app_idx 的动作（除 DISABLED、FACTORY_RESET）必须同时提供 `addr≠0x0000` 且 `app_idx≠0xFFFF`，否则返回 `err=2`（字段不合法）。

#### 8.2.4 RESET DEFAULTS

请求：

```text
Vendor SET 0x4C 0x01
```

成功返回：

```text
Vendor RET 0x4C 0x01 0x00
```

作用：

- 清空所有 APP 写入的按键配置
- 恢复到"全部 disabled + Key1 five_click 本地恢复出厂"的默认态
- 之后未配置按键触发**仍然静默**

### 8.3 LED 指示开关（`0x4C` 子码 `0x02`，v1.0.17 新增）

#### 8.3.1 设置开关

请求：

```text
Vendor SET 0x4C 0x02 <enable>
```

| 字段 | 类型 | 取值 | 含义 |
|---|---|---|---|
| `enable` | u8 | `0`=禁用 / `1`=启用，其它返回 `err=2` | LED 指示总开关 |

成功返回：

```text
Vendor RET 0x4C 0x02 0x00
```

错误码：`err=1` 长度错（payload < 1 字节）；`err=2` `enable` 不在 {0,1}；`err=3` 未知子码。

#### 8.3.2 查询开关

请求：

```text
Vendor GET 0x4C 0x02
```

成功返回：

```text
Vendor RET 0x4C 0x02 0x00 <enable>
```

#### 8.3.3 行为约束

- **持久化**：写入即落 NVS，断电不丢；恢复出厂会重置为 `1`（启用）
- **默认值**：首次烧录、恢复出厂后 = `1`（启用）
- **禁用范围**：`enable=0` 仅屏蔽以下 LED 表现：
  - 按键短按 / 长按指示
  - 配网完成 + 首次 Friendship 建立的 3s 常亮
  - APP 删除设备的 3s 常亮（但 reboot 仍然执行）
  - Key2+Key7 长按 60s 通信窗口的 3s 常亮
- **禁用不影响以下指示**（属硬性体验项）：
  - 上电 3s 常亮
  - Key1+Key8 长按恢复出厂的 4 次慢闪
  - 第 3 / 5 次上电触发的硬件复位指示（`bsp_sys` 内置）
- **优先级**：`Key1+Key8 出厂复位` > `上电` > `OTA 期间屏蔽` > `enable=0 屏蔽` > 其他业务事件

#### 8.3.4 LED 表现总表

| 事件 | LED 行为 | 受 enable 控制 | 备注 |
|---|---|---|---|
| 上电 | 常亮 3s | ❌ | `bsp_sys_init` 直接发 |
| 按键短按（CLICK / PRESS_RELEASE）— 未入网 | 慢闪 3 次（0.5s on / 0.5s off ×3） | ✔ | 短按 = release 即发 |
| 按键短按 — 已入网 | 快闪 1 次（约 250ms on） | ✔ | — |
| 按键长按起始（LONG_PRESS, ≥3000ms 边沿）— 未入网 | 慢闪 3 次 | ✔ | 与短按未入网相同（有意为之） |
| 按键长按 — 已入网 | 常亮直到松手（LONG_RELEASE 关闭） | ✔ | — |
| APP 配网完成 + **配网后首次** Friendship 建立 | 常亮 3s | ✔ | 用 NVS 一次性标志判断"首次" |
| APP 删除设备（`bt_mesh_reset` / `prov.reset`） | 常亮 3s 后 reboot | ✔（仅灯，reboot 必执行） | — |
| Key2+Key7 长按 3s（打开 60s 通信窗口） | 常亮 3s | ✔ | — |
| Key1+Key8 长按 3s（恢复出厂） | 0xCCCC 4 次慢闪（约 4s） | ❌ | 与硬件出厂复位绑定，最高优先级 |
| OTA 升级期间（ACTIVE / TRAFFIC） | **不亮**（屏蔽业务指示） | n/a | `mod_lpn_ota_mode` 自动通知 |
| 识别（identify） | 保持 `prov.c` 现有 LED 行为（`0xaaa` 等） | n/a | 用户决定不清理共用 prov.c |
| 固件升级中 | 不亮 | n/a | 同 OTA 屏蔽 |

详细 pattern 字节序与 250ms/bit 时间基准定义在 [`bsp_led.c`](../../e:/work/nrfConnect/SunSmrat-relase-54L15/src/bsp_led.c) 与需求规格 §R-2.2.10。

## 9. Generic Battery Server（Element 1）

设备在主元素挂载了 **Generic Battery Server（SIG Model ID 0x100C）**，用于向 APP/网关暴露电量信息。

### 9.1 数据来源

- 固件通过 SAADC 采样 VDD（overlay alias `battery-adc`，通道 VDD）
- 使用内置查表 + 线性插值把 mV 映射为 SoC：当前曲线为 CR2032/CR2016 近似（`3000mV→100%`、`2500mV→0%`）
- 采样在 Battery Server 收到 Get 时按需触发（`battery_get` → `bsp_battery_sample`）
- 固件**不主动周期性发布** Battery Status，APP 需要时主动 `Battery Get`

### 9.2 返回字段固定策略

当前实现（`bsp_battery_fill_status`）返回：

| 字段 | 取值 |
|---|---|
| `battery_lvl` | 0~100（实时 SoC；曲线未实测，仅参考） |
| `discharge_minutes` / `charge_minutes` | `BT_MESH_BATTERY_TIME_UNKNOWN` |
| `presence` | `PRESENT_REMOVABLE`（可拆卸电池） |
| `indicator` | `GOOD` / `LOW` / `CRITICALLY_LOW`（按 `BATTERY_MV_LOW/CRITICAL` 阈值） |
| `charging` | `NOT_CHARGEABLE`（本产品不可充电） |
| `service` | `NOT_REQUIRED` |

⚠ 产品最终形态若非 CR2032/CR2016，固件里 `_curve[]`（`bsp_battery.c:30-43`）与 `BATTERY_MV_LOW` / `BATTERY_MV_CRITICAL` 阈值需要调整。

## 10. Health Server 故障上报

设备在主元素挂载了 **Health Server**（SIG Model ID `0x0002`），通过标准 **Health Current Status** 消息（opcode `0x04`）主动上报故障。这是设备**唯一**会主动向网络发送的消息通道（按键 Client 报文是响应用户操作触发的，不算主动上报）。

### 10.1 按键卡住（Button Stuck）

- **触发条件**：任意按键按下后持续 ≥ 60 秒未释放
- **重复上报**：每次新的卡住事件都会上报一次；按键物理释放后固件自动清除 stuck 标记
- **无本地动作**：故障不触发设备复位、不关 LED，仅上报

Health Current Status 报文内容：

| 字段 | 值 |
|---|---|
| Test ID | `0x04`（HEALTH_TEST_BUTTON） |
| Company ID | `0x0A78`（小端：`78 0A`） |
| Fault Code | `0x21 + button_idx`，即 `0x21..0x28` 对应 Key1..Key8 |

示例（Key3 卡住）：`04 | 04 | 78 0A | 23`（opcode | test_id | cid_le | fault）

### 10.2 APP 必须完成的配置

Health Server 上报走 **发布（Publication）机制**。APP 在配网完成后**除了 AppKey Bind 以外**，必须额外下发 `Config Model Publication Set`，否则故障在 NVS 有记录但**空中不会有任何报文**——这是最常见的"设备不上报"排查点。

推荐参数：

| 配置项 | 推荐值 |
|---|---|
| Target | `Element 1 / Health Server (Model ID 0x0002)` |
| Publish Address | APP/网关订阅的组地址或网关单播 |
| AppKey Index | 与 Vendor Model 同一把即可 |
| Publish Period | `0`（事件触发，不周期发布；推荐） |
| Publish TTL | `7` |
| Publish Retransmit Count / Interval | `3` 次 / `50 ms`（LPN 节点建议多重传） |

### 10.3 LPN 特性对上报延迟的影响

- 故障上报**不会立刻发出**：Mesh 层会把 Health 消息放进 LPN 出队列，由 Friend 节点在下次 Poll 响应时一并拉走
- 典型延迟 = Friend Poll 间隔（数百 ms ~ 1 s）
- 若设备处于 `LPN_OTA` 通信窗口期（用户双击任意键后的 60 秒），延迟更低

### 10.4 故障持久化与查询

- 故障码会持久化到 NVS，设备重启后仍保留
- APP 可通过标准 **Health Fault Get**（solicited，ack-based）主动获取当前已注册故障列表，返回 **Health Fault Status**（opcode `0x05`）
- APP 通过 **Health Fault Clear** 清除后，Registered 列表中该 Company ID 对应条目被删除

### 10.5 故障码全量表

下列 Test ID 在固件枚举里有定义，**当前 LPN 产品实际启用的只有 `0x04 HEALTH_TEST_BUTTON`**。其余 Test ID 是全产品线共享的定义，LPN 不会触发，APP 侧不做硬编码假设即可。

| Test ID | 名称 | 是否 LPN 启用 |
| --- | --- | --- |
| `0x00` | HEALTH_TEST_4G | 否（LPN 无 4G） |
| `0x01` | HEALTH_TEST_MQTT | 否（LPN 无 MQTT） |
| `0x02` | HEALTH_TEST_GW | 否（LPN 非网关） |
| `0x03` | HEALTH_TEST_PROTECT | 否（LPN 无过流/过温负载） |
| `0x04` | **HEALTH_TEST_BUTTON** | 是 |

## 11. APP 联调建议

推荐首轮联调策略：

1. Provisioning 设备
2. 给 `Element 1 / Vendor Model` 绑定 AppKey（用于配置/查询通道）
3. 给 `Element 1 / Generic Battery Server` 绑定 AppKey（电量查询）
4. 给 `Element 1 / Health Server` 绑定 AppKey + 下 `Config Model Publication Set`（详见 §10.2）
5. 读取 `0x4C 0x01` 能力信息（trigger_count = 5）
6. 根据业务，逐键给 `Element 2~8` 绑定对应 Client Model 的 AppKey（用到哪个绑哪个）
7. 用 `0x4C SET` 明确写入需要的 `button + trigger` 动作（trigger 只能 0~4）
8. 不需要的触发可以不写（默认即静默），也可显式写 `disabled`，二者等价
9. 需要 OTA 或高频配置时，引导用户长按 `Key2+Key7` 3 秒打开 60s 通信窗口
10. 如需关闭 LED 业务指示（省电场景），用 `0x4C SET 0x02 0x00`；查询当前状态用 `0x4C GET 0x02`（详见 §8.3）

## 12. 当前已知限制

- **v0.2.6 新增**：休眠电流降至 **~8μA**，CR2032 寿命预估 ≥ 2 年；按键 wake 短窗口缩到 1s；combo 窗口期 Vendor SET 自动续期 30s
- **v1.0.17 新增**：`0x4C` 子码 `0x02` LED 指示开关（详见 §8.3）；持久化、默认启用、禁用时不影响上电与出厂复位指示
- **多击已全部取消**：`double_click / triple_click / five_click` 事件固件不再产生；`0x4C SET` 写 trigger ≥ 5 返回 `err=2`；老 NVS 里 trigger=5/6/7 的配置**永远触发不到**，但不影响新配置写入
- 组合键 `Key2+Key7 长按 3s` 保留给 60s 通信窗口、`Key1+Key8 长按 3s` 保留给本地恢复出厂，**两组不在 `0x4C` 协议范围内**，APP 不能配置也不会因按下向网络发任何消息
- 其他两键组合（非上述两对 + `COMBO_CLICK` / 其余 `COMBO_LONG_PRESS`）固件能识别但未绑定动作
- `STUCK`（按键卡住 ≥ 60 s）走 **Health Server Current Status** 上报，不通过 `0x4C` 协议配置（详见 §10）
- 未入网设备**上电进 60s 激活模式**，期间无配网动作 → 立即永久休眠（v0.2.6 由"10s 窗口 → 70s 总时长"改为"60s 一次性"，详见工程文档 §10.1.11）。后续唯一唤醒方式 = `Key2+Key7 长按 3s`
- 设备**不主动发送任何 Vendor EVENT**；除 Health Server 故障上报外，APP 不需要订阅任何固件主动上报地址
- 设备**不主动周期性发布 Battery Status**；APP 需要电量时主动 `Battery Get`
- 工厂复位（长按 Key1+Key8 3s）会自动发 Friend Clear 释放 Friend 槽位（v0.2.6 加 200ms 延迟保证消息送达）
- ⚠ **APP 重新配网避免重用旧 unicast 地址**：LPN 工厂复位后 SEQ 归零，若 APP 重用旧地址则灯端 RPL 仍记着旧 SEQ → Replay 全拒。建议手动改 unicast 或使用新地址。详见 §13
- `products` 里的 composition hash 仍未回填最终值

## 13. APP 重新配网注意事项（v0.2.6 新增）

LPN 工厂复位后 SEQ 计数器归零。如果 APP 给重新配网的 LPN 分配**相同 unicast 地址**：

1. 灯端的 RPL[`旧地址`] 记录着 LPN 重置前的高 SEQ（如 0x500）
2. LPN 重启后 SEQ 从 0 开始
3. 灯收到 SEQ < 0x500 的消息 → 全部判为 Replay → 拒绝
4. **按键完全不响应**，自然恢复要等几天到几周（看按键频率）

**APP 推荐策略**：

- 节点删除后**不立即释放 unicast 地址**，过期 N 天后再回收
- 或配网 UI 提供"手动指定 unicast"选项，让用户配新地址（避开 LPN 旧地址段）
- 极端情况引导用户**也工厂复位灯**（清 RPL）

固件侧已尽力（200ms 延迟保证 Friend Clear 送达释放槽位），**但 RPL 是协议规定的强制持久化，固件无法跨节点清除**。
