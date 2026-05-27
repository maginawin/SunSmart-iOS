# PRODUCT_2422K8N_US_4SC_AC APP 对接文档

> **本产品与 `PRODUCT_2422K8N_4DIM_AC` 硬件/软件完全相同，仅 PRODUCT_ID 不同**（用于 APP 区分两个销售型号）。所有 Mesh 协议、Vendor 私有协议、按键、LED、Health Server、SIG Time SRV、SD3077 RTC、OTA、配网流程**与 4DIM_AC 完全一致**。
>
> APP 对接的协议细节全部引用：
> **`D:\claude_code\ProjectDoc\PRODUCT_2422K8N_4DIM_AC\PRODUCT_2422K8N_4DIM_AC_APP对接文档.md`**
>
> 本文档仅列出与 4DIM_AC 的**差异点**。

---

## 1. 差异速查表

| 项 | `PRODUCT_2422K8N_4DIM_AC` | `PRODUCT_2422K8N_US_4SC_AC`（本产品） |
|---|---|---|
| **PRODUCT_ID** | `0x2A12`（小端 `12 2A`） | **`0x2A11`（小端 `11 2A`）** |
| **GATT/广播设备名** | `2422K8NACD` | **`2422K8NACS`** |
| Bootloader Banner | `2422K8N_4DIM_AC` | `2422K8N_US_4SC_AC`（仅启动 LOG） |
| Composition Hash | `456c3453` | **`6d3613bc`**（PID 不同导致 hash 不同） |
| Company ID | `0x0A78` | `0x0A78`（相同） |
| 硬件 | 共硬件家族（DIM 模组 + 8 主键 + SW1 + Status LED + SD3077 RTC + MS621FE） | **完全一致** |
| Element 数量 | 8 | **8（一致）** |
| Mesh 模型列表 | Element 1 含 Time SRV / Time Setup SRV / Vendor Setup SRV 等 | **完全一致** |
| Vendor 协议（0x4C/0x48/0x36 等） | v1.0.23 | **完全一致**（含 v1.0.23 新增 `0x4C 0x10` RTC 黑匣子查询） |
| 按键 / LED / Health / RTC / OTA 行为 | 详见 4DIM_AC 文档 | **完全一致** |

---

## 2. APP 端识别本产品的方式

### 2.1 通过 Manufacturer Data

```text
偏移  长度  含义                       本产品的值
0~1   2     Company ID (LE)            0x0A78
2~3   2     Product ID (LE)            0x2A11 （字节序 11 2A）  ★ 与 4DIM_AC 唯一区别
4~9   6     设备 BLE MAC               -
10    1     事件标志                    保留，0
11    1     custom_id                  保留，0
12~13 2     主元素地址 (LE)            -
```

### 2.2 通过 GATT 设备名

扫描 `2422K8NACS`（4DIM_AC 是 `2422K8NACD`）。

### 2.3 ⚠ 不要用 Bootloader Banner 识别

`2422K8N_US_4SC_AC` 仅在串口启动日志中可见，**APP 不可见**。请用 PID 或 GATT 设备名。

---

## 3. Composition Data Hash 差异

| 产品 | Hash | 含义 |
|---|---|---|
| `PRODUCT_2422K8N_4DIM_AC` | `456c3453` | OTA metadata 用 |
| `PRODUCT_2422K8N_US_4SC_AC` | **`6d3613bc`** | OTA metadata 用 |

⚠ **OTA 升级时 APP 必须用对应产品的 hash**——虽然两个产品的 Composition Data 结构（元素 + 模型列表）完全一致，但 PID 是 Composition Data 的一部分，PID 不同 → SIG 计算出的 hash 不同。**两个产品的固件不能交叉升级**。

---

## 4. 其它对接细节

⚠ **全部沿用 4DIM_AC 文档**。请直接打开：

```
D:\claude_code\ProjectDoc\PRODUCT_2422K8N_4DIM_AC\PRODUCT_2422K8N_4DIM_AC_APP对接文档.md
```

涉及内容（章节号沿用 4DIM_AC 文档）：

| 主题 | 4DIM_AC 文档章节 |
|---|---|
| Composition Data / Element 布局 / 10 SIG client × 8 按键 | §3 |
| APP 必须完成的 Mesh 配置 / AppKey 绑定 / Publication Set | §4 |
| GATT Proxy 常开、APP 直连时机 | §5 |
| 物理按键 / 触发判定 / 组合键 | §6 |
| 默认行为 / 未经配置的按键 | §7 |
| **Vendor 0x4C 协议**（按键配置 / LED 开关 / TX 开关 / TIME_PUBLISH / **RTC 黑匣子** v1.0.23 新增） | §8（含 §8.6 RTC 黑匣子查询） |
| Generic Battery Server **不挂载** | §9 |
| Health Server / 卡键上报 / RTC fault (0x21/0x22) | §10 |
| 调试要点 | §11 |
| 与 LPN 版 4DIM/4SC 的差异 | §12 |

---

## 5. 维护规则

- 任何协议更新（Vendor opcode、Health fault 码、SIG Time 行为、按键配置 wire 格式等）一律在 **4DIM_AC 文档**中维护
- 本文档**只在 PID / 设备名 / 硬件家族归属发生变化时**才需要更新
- 协议主文档：`D:\claude_code\sunricher_protocol_vendor\team-docs\sunricher_protocol_vendor.md`
- 协议维护规则：`D:\claude_code\sunricher_protocol_vendor\team-docs\sunricher-protocol-maintenance\references\protocol-maintenance-rules.md`
