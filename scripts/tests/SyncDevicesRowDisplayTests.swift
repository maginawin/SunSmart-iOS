func check(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fatalError(message) }
}
func makeDevice(_ address: Address) -> SyncDevicesModel {
    let device = SyncDevicesModel(name: "Device", address: address)
    let tasks = (0..<12).map { _ in SyncDeviceStepTaskModel() }
    let step = SyncDeviceStepModel(type: "Profile", state: .wait, tasks: tasks)
    step.parentDeviceModel = device
    tasks.forEach { $0.parentStepModel = step }
    device.steps = [step]
    return device
}
let context = SyncDevicesDisplayContext()
let device = makeDevice(1), waitingDevice = makeDevice(2)
let group = SyncDevicesGroupModel(groupName: "Group", groupAddress: 0xC000, deviceModels: [device, waitingDevice])
device.parentGroupModel = group
waitingDevice.parentGroupModel = group
let run = UUID()
context.beginRun(run)
let cell = DeviceCell(), groupCell = GroupCell()
cell.configure(with: device, displayState: context.state(for: device))
groupCell.configure(with: group, displayState: context.state(for: group))
check(cell.arrowImageView.isHidden && !cell.stateImageView.isHidden, "Unstarted device needs waiting icon")
check(cell.stateImageView.image?.name == "device_add_waiting", "Wrong waiting asset")
let step = device.steps[0]
for index in step.tasks.indices {
    let task = step.tasks[index]
    task.state = .inSettings
    context.taskDidStart(task, run: run)
    device.isShow = true
    cell.updateState(context.state(for: device))
    groupCell.updateState(context.state(for: group))
    check(!cell.arrowImageView.isHidden && cell.stateImageView.isHidden, "Running device must keep arrow")
    check(cell.arrowImageView.image?.name == "arrow_up", "Expanded arrow must point up")
    check(groupCell.stateImageView.isHidden, "Running Group must not revert to waiting")
    let writes = cell.arrowImageView.writes + cell.stateImageView.writes + groupCell.stateImageView.writes
    let constraints = cell.stateImageView.snp.updates + groupCell.stateImageView.snp.updates
    task.state = index == 0 ? .failed : .successful
    cell.updateState(context.state(for: device))
    groupCell.updateState(context.state(for: group))
    if index < 11 {
        check(device.state == .wait, "Must exercise actual aggregate wait between tasks")
        check(!cell.arrowImageView.isHidden && cell.stateImageView.isHidden, "Inter-task gap flashes waiting")
        check(writes == cell.arrowImageView.writes + cell.stateImageView.writes + groupCell.stateImageView.writes, "Stable UI must not rewrite image or visibility")
        check(constraints == cell.stateImageView.snp.updates + groupCell.stateImageView.snp.updates, "Stable UI must not update constraints")
        check(context.state(for: waitingDevice) == .wait, "Unstarted sibling incorrectly appears active")
    }
}
check(context.state(for: device) == .failed && !cell.stateImageView.isHidden, "Real failure must be visible immediately")
print("PASS: 12 tasks with failed first task, stable arrow and Group, no repeated UI writes")
// 保留成功任务重试：即使聚合状态因历史成功步骤成为 inSettings，也不能提前显示本轮运行。
let completed = SyncDeviceStepModel(type: "Done", state: .successful, tasks: [])
completed.parentDeviceModel = device
device.steps.append(completed)
step.tasks[0].state = .wait
let retryRun = UUID()
context.beginRun(retryRun)
check(device.state == .inSettings, "Fixture needs history-induced aggregate inSettings")
check(context.state(for: device) == .wait, "Retry history must not mark current run started")
context.taskDidStart(step.tasks[0], run: run)
check(context.state(for: device) == .wait, "Old run callback must be ignored")
context.taskDidStart(step.tasks[0], run: retryRun)
check(context.state(for: device) == .inSettings, "Current run start must be recorded")
cell.prepareForReuse()
cell.configure(with: waitingDevice, displayState: context.state(for: waitingDevice))
check(cell.arrowImageView.isHidden, "Reused cell must show waiting for another device")
cell.prepareForReuse()
cell.configure(with: device, displayState: context.state(for: device))
check(!cell.arrowImageView.isHidden && cell.stateImageView.isHidden, "Offscreen return must retain active display")
device.isShow = false
cell.updateState(context.state(for: device))
check(cell.arrowImageView.image?.name == "arrow_down", "Arrow direction changes must bypass snapshot guard")
step.tasks[0].state = .successful
cell.updateState(context.state(for: device))
check(cell.stateImageView.image?.name == "sync_success_small", "Success must update promptly")
context.invalidateRun()
step.tasks[0].state = .wait
context.taskDidStart(step.tasks[0], run: retryRun)
check(context.state(for: device) == device.state, "Invalidated run must fall back to business state")
print("PASS: retry, stale start, offscreen reuse, direction change, success and invalidation")
let leaf = SyncDevicesModel(name: "Leaf", address: 3)
leaf.state = .inSettings
cell.model = leaf // 共用读取页面的兼容绑定入口。
check(cell.arrowImageView.isHidden && cell.stateImageView.layer.active, "Leaf must keep spinner without arrow")
let starts = cell.stateImageView.layer.starts
leaf.isSelected = true
cell.updateState(.inSettings)
check(cell.stateImageView.layer.starts == starts, "Selection refresh must not restart spinner")
leaf.state = .failed
leaf.failedCount = 2
leaf.isFineshed = true
cell.updateState(.failed)
check(!cell.failureLabel.isHidden && !cell.resyncBtn.isHidden && !cell.selectedImageView.isHidden, "Failure, finish and retry controls must refresh")
check(!cell.stateImageView.layer.active, "Failure must stop spinner")
groupCell.clearBinding()
groupCell.stateImageView.isHidden = true // Proxy 专用绑定。
groupCell.arrowImageView.isHidden = true
let proxyWrites = groupCell.stateImageView.writes
groupCell.updateState(.failed)
check(groupCell.groupModel == nil && groupCell.stateImageView.writes == proxyWrites, "Proxy must not reuse previous Group binding")
groupCell.configure(with: group, displayState: .failed)
group.isFineshed = true
group.isSelected = true
groupCell.updateState(.failed)
check(!groupCell.selectBtn.isHidden && groupCell.selectBtn.isSelected, "Group finish/selection must refresh")
print("PASS: shared binding, leaf animation, failure controls, Proxy reuse and Group selection")
