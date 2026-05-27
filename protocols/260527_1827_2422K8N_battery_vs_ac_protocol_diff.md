# 2422K8N Battery Power Switch 与 AC Power Switch 协议差异总结

## 1. 对比范围

来源文件：

- `protocols/2422K8N_US_4DIM.md`：Battery power switch，覆盖 PID `0x2A01` / `0x2A02`
- `protocols/2422K8N-4SC-AC-US.md`：AC power switch，覆盖 PID `0x2A11` / `0x2A12`

辅助核对文件：

- `protocols/0x2A01.json`
- `protocols/0x2A02.json`
- `protocols/0x2A11.json`
- `protocols/0x2A12.json`

注意：`2422K8N-4SC-AC-US.md` 是差异文档，完整 AC 协议引用外部 `PRODUCT_2422K8N_4DIM_AC_APP对接文档.md`。当前目录没有该主文档，因此本文只总结当前仓库可直接验证的信息，并单独标出需要回源确认的点。

## 2. 总体结论

两组产品不是简单 PID 差异。核心差别是节点供电形态与在线模型：

| 维度 | Battery power switch (`0x2A01` / `0x2A02`) | AC power switch (`0x2A11` / `0x2A12`) |
|---|---|---|
| 供电/节点形态 | 电池低功耗 LPN 遥控器 | 市电 AC 常在线开关 |
| 产品分类 | `Battery` | AC power switch / 4DIM_AC 家族 |
| 主要接入约束 | 平时睡眠或 LPN 运行，配置/OTA 依赖 60s 通信窗口 | 非 LPN，文档说明 GATT Proxy 常开，APP 可直接连接时机更宽 |
| PID 关系 | `0x2A01` 与 `0x2A02` 同构，仅 PID 不同 | `0x2A11` 与 `0x2A12` 同构，仅 PID / 广播名 / hash 不同 |
| Element 数量 | 8 | 8 |
| 按键模型方向 | 8 键均作为 SIG Client 发控制命令 | 同为 8 主键 Client 控制能力，且 AC 文档声明与 4DIM_AC 完全一致 |
| 电池模型 | 挂载 Generic Battery Server | 明确不挂载 Generic Battery Server |
| Time / RTC | 未描述 SIG Time / RTC 能力 | 有 SIG Time Server / Time Setup Server、SD3077 RTC、RTC fault 与 RTC 黑匣子 |
| Health 故障 | 主要为按键卡住 | 按键卡住 + RTC fault (`0x21` / `0x22`) |
| Vendor 扩展 | `0x4C` 按键配置、LED、TX、OTA 等 | 继承同类 Vendor 协议，并含 v1.0.23 的 `0x4C 0x10` RTC 黑匣子查询 |

## 3. 识别信息差异

### 3.1 PID 与广播名

| 产品 | PID | 小端字节序 | GATT/广播名 | Composition Hash |
|---|---:|---|---|---|
| Battery 4SC | `0x2A01` | `01 2A` | 原文未单独给出；文档说明与 4DIM 同构，仅 PID 不同 | `0a833eac` |
| Battery 4DIM | `0x2A02` | `02 2A` | `2422K8NUSD` | `460a9a8a` |
| AC 4SC | `0x2A11` | `11 2A` | `2422K8NACS` | `6d3613bc` |
| AC 4DIM | `0x2A12` | `12 2A` | `2422K8NACD` | `456c3453` |

APP 识别建议：

- 两组协议都应优先通过 Manufacturer Data 的 Product ID 识别。
- 不要用 Bootloader Banner 作为 APP 识别依据；两份文档都明确 Banner 只是启动日志，不是 APP 可见扫描名。
- AC `0x2A11` 与 `0x2A12` 虽然 Composition Data 结构一致，但 PID 参与 hash 计算，OTA metadata 必须按 PID 区分，不能交叉升级。

### 3.2 Manufacturer Data

两组 Manufacturer Data 的结构一致：

| 偏移 | 长度 | 含义 |
|---|---:|---|
| 0~1 | 2 | Company ID，小端，`0x0A78` |
| 2~3 | 2 | Product ID，小端 |
| 4~9 | 6 | BLE MAC |
| 10 | 1 | 事件标志或保留 |
| 11 | 1 | `custom_id` |
| 12~13 | 2 | 主元素地址，小端 |

差别只在 Product ID 值：Battery 使用 `0x2A01` / `0x2A02`，AC 使用 `0x2A11` / `0x2A12`。

## 4. Mesh Features 与在线行为差异

辅助 JSON 中的 feature 差异如下：

| PID | Relay | Proxy | Friend | Low Power |
|---|---:|---:|---:|---:|
| `0x2A01` | 0 | 2 | 0 | 2 |
| `0x2A02` | 0 | 2 | 0 | 2 |
| `0x2A11` | 2 | 2 | 2 | 0 |
| `0x2A12` | 2 | 2 | 2 | 0 |

协议含义：

- Battery 版是 LPN 节点：Relay / Friend 关闭，GATT Proxy 编译启用但运行时动态开关；`LPN_RUN` 下扫描不到 Proxy 是正常行为。
- Battery 版配置、查询、OTA 或批量 `0x4C` 操作，需要引导用户长按 `Key2 + Key7` 3 秒打开 60 秒通信窗口，或利用配网完成后的 60 秒 Config 宽限期。
- AC 版不是 LPN，文档将 GATT Proxy 描述为常开，APP 配置与查询不需要依赖 Battery 版那套低功耗唤醒窗口。

## 5. Composition / Model 差异

两份 Markdown 均描述为 8-element 结构，并且按键以独立 element 作为 SIG Client 控制源地址：

- Key1 对应主元素 `primary + 0`
- Key2~Key8 对应 `primary + 1`~`primary + 7`
- SIG DFU Server / BLOB Server 位于 Element 2，与 Key2 共用 element

主要模型差异：

| 模型能力 | Battery | AC |
|---|---|---|
| Config Server / Health Server | 有 | 有 |
| Sunricher Vendor Setup Server | 有 | 有 |
| 每键 SIG Client | 文档描述为 10 个 Client：OnOff / Level / LC / Scene / Lightness / CTL / HSL / Power Level / Power OnOff / DTT | AC JSON 显示同样包含扩展 Client |
| Generic Battery Server (`0x100C`) | 有，挂主元素 | 无，AC 文档明确“不挂载” |
| Time Server (`0x1200`) / Time Setup Server (`0x1201`) | 无 | 有，挂主元素 |
| RTC 相关能力 | 无 | 有 SD3077 RTC、RTC fault、RTC 黑匣子 |
| DFU Server / BLOB Server (`0x1400` / `0x1402`) | 有 | 有 |

对 APP 的影响：

- Battery 版需要给 Generic Battery Server 绑定 AppKey，并按需配置 Battery Server Publication。
- AC 版不要按 Battery 版逻辑查 Generic Battery Server；应按 AC 协议处理 Time / RTC 能力。
- 两组都不应硬编码按键 element 偏移，仍建议通过 Composition Data Get 动态发现 element 和 model。

## 6. `0x4C` Vendor 协议差异

共通点：

- 都使用 Sunricher Vendor Model。
- 都以 `0x4C` 承载按键配置、LED 开关、按键 TX 开关等能力。
- 按键 action_type 已扩展到富指令集合，覆盖 OnOff、Level、Scene、Lightness、CTL、HSL、Power Level、Power OnOff、DTT 等类型。
- 触发维度仍是按键触发类型，不应把 `trigger_count` 和 `action_type` 上限混淆。

差异点：

| 子能力 | Battery | AC |
|---|---|---|
| 通信窗口续期 | 仅 Key2+Key7 combo 窗口内 Vendor SET 可续期 30s；post-prov、按键 wake、OTA 窗口不按 config traffic 续期 | 不依赖该 LPN 通信窗口机制 |
| TIME_PUBLISH | Battery 文档中作为 action_type 存在，但未描述 RTC / Time Server 体系 | AC 文档明确有 SIG Time SRV / RTC，并在引用章节中列出 TIME_PUBLISH |
| RTC 黑匣子 | 无 | 有，v1.0.23 新增 `0x4C 0x10` RTC 黑匣子查询 |
| 电量相关 | Battery 通过 SIG Generic Battery Server，不通过 `0x4C` 主路径表达 | AC 不挂 Battery Server |

## 7. Health / 上报差异

Battery：

- Health Server 用于按键卡住上报。
- 任意按键按下持续 60 秒触发 fault。
- 按键释放后发送空 fault array 表示恢复。
- APP 必须为 Health Server 配置 Publication，否则空中不可见。

AC：

- 继承按键 / LED / Health 行为。
- 额外包含 RTC fault，文档列出 `0x21` / `0x22`。
- APP 除按键卡住外，还需要解析 RTC 相关故障。

## 8. OTA 差异

两组都具备 OTA / DFU 能力，但 APP 侧注意点不同：

- Battery 版 OTA 受低功耗通信窗口影响，优先通过本机 GATT Proxy 窗口直连，平时 `LPN_RUN` 下不可直接扫描 Proxy。
- AC 版不受 LPN 窗口限制，但 `0x2A11` 和 `0x2A12` 的 Composition Hash 不同，OTA metadata 必须区分。
- Battery 版 `0x2A01` / `0x2A02` 也需要按各自 hash 登记 OTA metadata。

## 9. APP 集成差异清单

APP 产品表至少需要区分四个 PID：

- Battery：`0x2A01`、`0x2A02`
- AC：`0x2A11`、`0x2A12`

配置流程分支：

- Battery 分支需要处理 LPN 通信窗口、低功耗扫描不可见、Battery Server 绑定与电量读取。
- AC 分支需要处理常在线 Proxy、Time Server / Time Setup Server、RTC fault、RTC 黑匣子。
- 两组都需要处理 8 个按键 element 的 SIG Client 绑定、Vendor Model 绑定、Health Server Publication。

UI / 交互提示分支：

- Battery 版需要提示用户通过 `Key2 + Key7` 长按 3 秒打开配置/OTA 通信窗口。
- AC 版不应显示 Battery 低功耗唤醒式提示；应提供 RTC / Time 相关诊断或维护入口。

数据解析分支：

- Battery 收到 Battery Status 时按电量与 indicator 提示。
- AC 不应期待 Battery Status；需要解析 RTC fault 与 RTC 黑匣子返回。

## 10. 当前目录辅助文件的同步风险

以下是比较 Markdown 与本目录 JSON 时发现的风险，建议后续回源确认：

1. `2422K8N_US_4DIM.md` 已说明 Battery 版 v1.0.18 起每键 SIG Client 由 5 个扩展为 10 个，但 `0x2A01.json` / `0x2A02.json` 当前只列出基础 5 个 Client，缺少 `CTL` / `HSL` / `Power Level` / `Power OnOff` / `DTT`。如果这两个 JSON 被 APP 或测试用例使用，需要确认是否已过期。
2. Battery 文档中把 Generic Power Level Client 标为 `0x100D`，而 AC JSON 中使用 `0x100B`。按 SIG Mesh 常见模型编号，`0x100B` 更符合 Generic Power Level Client；建议回源核对 Battery 文档是否存在模型 ID 笔误。
3. `2422K8N-4SC-AC-US.md` 依赖外部 4DIM_AC 主文档，当前仓库无法直接核对 AC 的完整 `0x4C` wire、RTC 黑匣子 payload、组合键细节和 LED 行为细节。若要作为 APP 开发唯一依据，应补充或同步 4DIM_AC 主协议文档到当前 `protocols/`。

