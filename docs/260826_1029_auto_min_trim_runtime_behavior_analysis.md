# Auto min 与 High/Low-end trim 运行行为分析

> 分析日期：2026-08-26  
> 工程范围：`ttl-test` worktree  
> 用户复现：新建 `Occupancy sensing with daylight harvesting` 空 Group，Auto min 初始为 `N/A`；Low-end 从 `1%` 调为 `10%` 后变成 `100%`，随后 High-end 从 `100%` 调为 `80%` 后变成 `80%`。

## 1. 结论

用户建议的产品规则正确：

- Auto min 为 `N/A` 时，调整 High-end/Low-end trim 必须保持关闭，不改变其值。
- Auto min 为有效值 `X` 时：
  - `X > High-end trim` 才改为 High-end trim；
  - `X < Low-end trim` 才改为 Low-end trim；
  - 位于范围内则保持不变。

复现数值 `255 → 100 → 80` 与当前提交基线中的旧算法完全一致，不是随机 UI 显示问题。

## 2. 当前提交基线为何产生该现象

提交基线在 `ProfileSettingsViewController` 的 High/Low 回调中，对三种 daylight Profile 直接执行通用范围夹取：

- 新建 Profile 的 Auto min 关闭哨兵是 `255`。
- Low-end 改为 `10`、High-end 仍为 `100` 时，`255` 不在 `10...100` 内，因此被夹成 `100`。
- 之后 High-end 改为 `80` 时，`100` 不在 `10...80` 内，因此被继续夹成 `80`。
- 基线的 enabled 判断是“只要不等于 `255` 就启用”，所以 `100`、`80` 都会显示为已启用百分比。
- 同步层只认可 Auto min 的协议有效范围，导致 UI 与同步含义进一步分叉。

因此用户观察到的两个数值，直接证明运行中的 App 使用了这条旧夹取逻辑。

## 3. 当前 worktree 未提交修复的行为

当前 worktree 已将旧夹取替换为模型方法：

1. 先把 Auto min 按 `0...30` 有效值、`255` 关闭进行规范化。
2. 如果是关闭状态，立即返回，不参与 trim 夹取。
3. 只有有效且启用的值才与新的 Low/High 范围比较并夹取。
4. UI enabled 判断也改为仅认可 `0...30`。

在正常 UI 约束下，Low-end 可选 `0...30`，High-end 可选 `50...100`，因此该实现与用户建议等价：

| 初始 Auto min | 新 Low/High | 当前 worktree 预期 |
| ---: | --- | ---: |
| `255/N/A` | `10...100` | `255/N/A` |
| `255/N/A` | `10...80` | `255/N/A` |
| `5` | `10...100` | `10` |
| `20` | `10...100` | `20` |
| `30` | `10...80` | `30` |

当前工程搜索仅发现一个 `ProfileSettingsViewController` 和一条有效 High/Low 更新入口，没有第二份控制器或另一条仍在使用旧算法的源码路径。

## 4. 运行结果与源码不一致的判断

如果实际运行仍出现 `255 → 100 → 80`，则运行二进制没有包含当前 worktree 的未提交修复。常见原因包括：

- 运行了其它 worktree、分支或旧 DerivedData 产物；
- 只执行了 generic iPhoneOS 构建，但没有把该产物安装到测试设备；
- 测试设备仍在运行此前安装的 App。

此前四品牌 generic iPhoneOS build 只证明源码可编译，不会自动安装或替换设备上的 App；源码契约也不能代替真机 UI 验收。用户此次复现正好补充了这一验证边界。

## 5. 额外检查

`Profile.LightData.data` 中仍存在 disabled 时把内部展示用 `autoMinLevel` 临时初始化为 Low-end 的历史逻辑，但目前业务 UI 直接读取 `Profile.lightControlData`，High/Low 编辑回调也直接修改 `LightControlData`；该旧计算不是本次 `100 → 80` 的实际写回来源。后续若重新启用基于 `LightData.data` 的旧代码，需要单独清理这一潜在语义歧义。

## 6. 建议验收

用当前 `ttl-test` worktree 重新构建设备可安装版本后，至少验证：

- `N/A` 下 Low `1 → 10` 后仍为 `N/A`；
- 随后 High `100 → 80` 后仍为 `N/A`；
- Auto min `5%` 下 Low `1 → 10` 后变为 `10%`；
- Auto min `20%` 下调整为 `10...80` 后保持 `20%`；
- General、Day、Night 三份数据均遵循相同规则；
- 保存退出并重新进入后状态不回退。
