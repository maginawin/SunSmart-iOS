#!/usr/bin/env python3
"""运行生产进度更新方法的状态回归；UI 替身不代替真机布局验收。"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'SunSmart/Main/Space/View/SyncDeviceStepViewCell.swift').read_text()
models = (root / 'SunSmart/Main/Space/Model/SyncDevicesCellModel.swift').read_text()
base = models[models.index('enum SyncDevicesState'):models.index('struct SunricherVendorSetUnacknowledged')]
step = models[models.index('class SyncDeviceStepModel:'):models.index('class SyncDeviceStepTaskModel:')]
method = source[source.index('    func updateProgress()'):source.index('    override init')]
fixture = '''import Foundation
class CAAnimation {}
class SyncDevicesModel: SyncCellModel {}
class SyncDeviceStepTaskModel: SyncCellModel {
    var failedCount = 0
    var relevanceTaskModels: [SyncDeviceStepTaskModel] = []
}
struct UIImage { init?(named: String) {} }
final class Layer {
    var starts = 0
    var active = false
    func animation(forKey: String) -> CAAnimation? { active ? CAAnimation() : nil }
    func removeAnimation(forKey: String) { active = false }
    func addRotationAnimation(duration: Double, repeatCount: Int, animationKey: String) {
        starts += 1; active = true
    }
}
final class View {
    var writes = 0
    var text: String? { didSet { writes += 1 } }
    var isHidden = false
    var image: UIImage?
    let layer = Layer()
}
final class Cell {
    var stepModel: SyncDeviceStepModel?
    var displayedState: SyncDevicesState?
    var displayedFinished: Bool?
    var displayedFailure: Bool?
    let progressLabel = View(), resyncBtn = View(), failureLabel = View(), stateImageView = View()
'''
tests = '''
}
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}
let tasks = (0..<12).map { _ in SyncDeviceStepTaskModel() }
let model = SyncDeviceStepModel(type: "Profile", state: .wait, tasks: tasks)
let cell = Cell()
cell.stepModel = model
cell.updateProgress()
check(cell.progressLabel.isHidden, "Initial waiting progress must be hidden")
for index in tasks.indices {
    tasks[index].state = .inSettings
    cell.updateProgress()
    check(cell.progressLabel.text == "\\(index)/12", "Incorrect running count")
    check(!cell.progressLabel.isHidden, "Running progress must stay visible")
    let writes = cell.progressLabel.writes
    cell.updateProgress()
    check(cell.progressLabel.writes == writes, "Unchanged text must not be reassigned")
    tasks[index].state = .successful
    cell.updateProgress()
    check(cell.progressLabel.text == "\\(index + 1)/12", "Incorrect completed count")
    if index < tasks.count - 1 {
        check(model.state == .wait, "Fixture must exercise the real inter-task wait state")
        check(!cell.progressLabel.isHidden, "Progress flickers during the inter-task gap")
        check(cell.stateImageView.layer.active, "Spinner must stay active between tasks")
    }
}
check(cell.stateImageView.layer.starts == 1, "Progress updates must not restart the spinner")
check(cell.progressLabel.isHidden, "Completed step must retain its success presentation")
check(!cell.stateImageView.layer.active, "Completed spinner must stop")
print("PASS: 12 tasks, including 9/12 -> 10/12 and inter-task gaps; one continuous spinner")
tasks[11].state = .failed
tasks[11].failedCount = 2
model.isFineshed = true
cell.updateProgress()
check(!cell.failureLabel.isHidden && !cell.resyncBtn.isHidden, "Repeated failure must offer retry")
check(cell.progressLabel.text == "11/12" && !cell.progressLabel.isHidden, "Failure count must remain visible")
tasks[11].state = .inSettings
tasks[11].failedCount = 0
model.isFineshed = false
cell.updateProgress()
check(cell.failureLabel.isHidden && cell.resyncBtn.isHidden, "Retry must clear failure controls")
check(cell.stateImageView.layer.starts == 2, "Retry must start exactly one new spinner")
model.showProgress = false
cell.updateProgress()
check(cell.progressLabel.text == nil, "Hidden-progress steps must clear their text")
print("PASS: repeated failure, retry, and showProgress=false")
let first = SyncDeviceStepTaskModel(), second = SyncDeviceStepTaskModel()
first.state = .failed
let failedFirst = SyncDeviceStepModel(type: "Profile", state: .wait, tasks: [first, second])
cell.stepModel = failedFirst
cell.displayedState = nil
cell.updateProgress()
check(failedFirst.state == .wait && failedFirst.current == 0, "Fixture must exercise failure before any success")
check(cell.progressLabel.text == "0/2" && !cell.progressLabel.isHidden, "A failed first task must not hide progress between tasks")
print("PASS: failed first task keeps 0/N visible before the next task")
'''
with tempfile.TemporaryDirectory(prefix='sync-progress-') as directory:
    out = Path(directory) / 'SyncDevicesProgressRegression.swift'
    binary = Path(directory) / 'SyncDevicesProgressRegression'
    out.write_text(fixture.replace('final class Cell {', base + step + '\nfinal class Cell {') + method + tests)
    subprocess.run(['swiftc', str(out), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
