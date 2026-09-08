#!/usr/bin/env python3
"""验证生产显示上下文及 Cell 更新行为；控件替身不替代 UIKit 实际布局。"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def section(text, start, end):
    return text[text.index(start):text.index(end, text.index(start))]

def model_source():
    text = (ROOT / 'SunSmart/Main/Space/Model/SyncDevicesCellModel.swift').read_text()
    base = section(text, 'enum SyncDevicesState', 'struct SunricherVendorSetUnacknowledged')
    models = section(text, 'class SyncDevicesGroupModel:', 'class SyncDeviceStepTaskModel:')
    # 仅排除与显示无关的 SDK Group 解析属性，保留生产状态聚合及父级关系。
    models = models.replace(section(models, '    /// 所属group', '    init(name: String, address: Address)'), '')
    context = text[text.index('/// 当前同步轮次的显示上下文'):]
    return base + models + context

STUB_MODELS = '''
typealias Address = UInt16
struct DeviceOperationType {}
class SyncDeviceStepTaskModel: SyncCellModel {
    var failedCount = 0
    var relevanceTaskModels: [SyncDeviceStepTaskModel] = []
    var parentStepModel: SyncDeviceStepModel?
}
'''

UI_STUBS = '''
class CAAnimation {}
struct UIImage: Equatable {
    let name: String
    init?(named: String) { name = named }
}
func SCRXFrom(_ value: Double) -> Double { value }
final class Layer {
    var starts = 0, removes = 0
    var active = false
    func animation(forKey: String) -> CAAnimation? { active ? CAAnimation() : nil }
    func removeAnimation(forKey: String) { removes += 1; active = false }
    func addRotationAnimation(duration: Double, repeatCount: Int, animationKey: String) {
        starts += 1; active = true
    }
}
final class Constraints {
    var updates = 0
    var right: Constraints { self }
    var left: Constraints { self }
    func equalTo(_ value: Double) {}
    func updateConstraints(_ body: (Constraints) -> Void) { updates += 1; body(self) }
}
final class View {
    var writes = 0
    var text: String? { didSet { writes += 1 } }
    var isHidden = false { didSet { writes += 1 } }
    var isSelected = false { didSet { writes += 1 } }
    var isUserInteractionEnabled = false { didSet { writes += 1 } }
    var image: UIImage? { didSet { writes += 1 } }
    let layer = Layer(), snp = Constraints()
    enum State { case normal }
    func setImage(_ image: UIImage?, for state: State) { self.image = image }
}
class CellBase { func prepareForReuse() {} }
'''

def cell_source(filename, name, controls):
    source = (ROOT / 'SunSmart/Main/Space/View' / filename).read_text()
    methods = section(source, '    private struct DisplaySnapshot', '    override init')
    fields = ', '.join(control + ' = View()' for control in controls)
    return 'final class ' + name + ': CellBase {\nlet ' + fields + '\n' + methods + '\n}\n'

def main():
    cells = cell_source('SyncDeviceViewCell.swift', 'DeviceCell', ['nameLabel', 'iconImageBtn', 'selectedImageView', 'stateImageView', 'arrowImageView', 'failureLabel', 'resyncBtn'])
    cells += cell_source('SyncDevicesGroupViewCell.swift', 'GroupCell', ['nameLabel', 'iconImageBtn', 'stateImageView', 'arrowImageView', 'selectBtn'])
    tests = (ROOT / 'scripts/tests/SyncDevicesRowDisplayTests.swift').read_text()
    with tempfile.TemporaryDirectory(prefix='sync-row-display-') as directory:
        source = Path(directory) / 'Regression.swift'
        binary = Path(directory) / 'Regression'
        source.write_text('import Foundation\n' + STUB_MODELS + UI_STUBS + model_source() + cells + tests)
        subprocess.run(['swiftc', str(source), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True)

if __name__ == '__main__':
    main()
