# Scene OFF 同步状态问题根因与修复计划

## 背景

问题场景：在修改或创建场景时，最终场景为 OFF；如果过程中改过色温或亮度，点击 SAVE 后 Sync device(s) 页面提示成功，但返回上级页面后仍提示需要同步。

## 结论

当前 OFF 场景实际下发命令路径符合预期：当 `SceneExecuteData.isOn == false` 时，场景同步消息只生成 `GenericOnOffSet(false)` 和 `SceneStore`，不会继续生成亮度或色温命令。

Sync device(s) 页面提示成功也符合当前代码：`DeviceOperationType.isSuccessful` 对 OFF 场景做了特殊判断，只要设备缓存的场景 `isOn == false` 就认为成功，不再比较 lightness 和 CCT。

返回上级页面后仍提示需要同步的根因是另一条“是否需要同步”的判断路径没有同步更新：`Group.getNeedSyncNodes` 和 `NodeSyncData.syncScenes` 使用共享的 `SceneExecuteData.isSynced(with:for:)`。该方法虽然已经把 OFF 的 lightness 归零，但仍会在支持 CCT 的设备上比较 `cct == target.cct`。因此 OFF 场景里改了色温后，实际未下发 CCT，设备缓存的场景 CCT 仍是原值，`isSynced` 返回 false，页面就继续提示需要同步。

## 涉及文件

- `SunSmart/Common/Data/Node+MessageHandles.swift`
  - 当前 OFF 下发命令逻辑已正确。
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
  - `SceneExecuteData.deviceTarget(for:)`
  - `SceneExecuteData.isSynced(with:for:)`
  - `Group.getNeedSyncNodes`
  - `Node.updateData(message:isSuccess:)` 的 `SceneStore` 分支
- `SunSmart/Common/Data/Node+SyncData.swift`
  - `NodeSyncData.syncScenes` 通过 `isSynced` 判断是否需要同步。
- `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  - 当前 Sync device(s) 成功判断已对 OFF 特判，但应尽量回收成使用共享同步语义。
- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift`
  - 也使用 `isSynced`，需要确认共享语义变化不会影响消防相关场景。

## 修复原则

OFF 场景的同步语义应统一为：只关心场景编号、状态和 OnOff 结果，不比较 lightness 或 CCT。因为 OFF 下发时不会发送亮度和色温，保存场景时设备实际保存的是当时设备已有的亮度/色温状态；这些值不应导致 OFF 场景继续被判定为未同步。

不要通过把组场景的 CCT 写入设备缓存来掩盖问题。那会让本地缓存表达一个设备并未实际收到的 CCT，后续 ON 场景或设备状态判断更容易混乱。

## 修复计划

1. 修改 `SceneExecuteData.isSynced(with:for:)`
   - 保留 sceneNumber、isOn、state 的基础比较。
   - 当目标 `groupSceneData.deviceTarget(for: node).isOn == false` 时，直接返回 true，不再比较 lightness 和 CCT。
   - 当目标为 ON 时，保留现有 lightness 比较和 CCT 支持判断。

2. 回收 `DeviceOperationType.isSuccessful` 的 OFF 特判
   - 让普通同步成功判断也使用 `nodeScene.isSynced(with: sceneData, for: node)`。
   - 这样 Sync device(s) 页面和返回后“是否还需同步”使用同一套语义，避免再次分叉。

3. 检查消防同步模型
   - `EmerFireAlarmSyncCellModel` 已经使用 `isSynced`。
   - 因为共享语义变化只影响 OFF 场景不比较 lightness/CCT，符合本次需求。

4. 保持 `SceneStore` 缓存更新逻辑不伪造 CCT
   - OFF 后本地 node scene 可以记录 `isOn == false`、`lightness == 0`，CCT 保持设备当前实际状态。
   - 是否同步由 `isSynced` 决定，不要求缓存 CCT 等于组场景 CCT。

5. 验证
   - 构建验证：运行 iPhoneOS Debug 构建。
   - 代码路径验证：
     - OFF 场景改 CCT 后 SAVE，消息列表仍只有 `GenericOnOffSet(false)` 和 `SceneStore`。
     - Sync device(s) 成功判断与返回后 need sync 判断均走 `isSynced`。
     - OFF 场景下 `isSynced` 不比较 lightness/CCT。
     - ON 场景仍保留原 lightness/CCT 比较。

## 风险

这个修复会改变所有调用 `isSynced` 的 OFF 场景判断语义。该变化符合本次需求，但需要注意：如果未来产品希望 OFF 场景也预存一个“恢复 ON 时使用的 CCT/亮度”，那将是另一个业务模型，不能复用当前“OFF 只下发 OnOff”的语义。
