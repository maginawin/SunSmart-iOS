"""Join production Scheduler wire/cache/completion code to the SQLite fixture.

BLE, UIKit, Node/Model identity, the property table and queue admission are controlled boundaries.
The packet codec, observation ownership, Node ACK application, Proxy completion,
App result/binding coordinator, SDK property serialization and Schedule SQLite persistence
are production code. Property bytes also round-trip through a fixture SQLite table.
"""
from check_scene_configuration import function


def expand(source, root, sdk):
    base = sdk / 'Sources/NordicSigMeshSDK/nRFMeshProvision'
    lib = sdk / 'Sources/NordicSigMeshSDK/MeshLib'
    source = source.replace('typealias SceneNumber = UInt16', 'public typealias SceneNumber = UInt16')
    source = source.replace('typealias SchedulerAction = Schedule.Action\n', '')
    source = source.replace('typealias SchedulerRegistryEntry = Entry', 'typealias Entry = SchedulerRegistryEntry')
    source = source.replace(function(source, 'enum WeekDay:'), '')
    source = source.replace(function(source, '    enum Action:'), '    typealias Action = SchedulerAction')
    schedule = (root / 'SunSmart/Main/Timed/Model/Scheduler.swift').read_text()
    source = source.replace(function(source, '    var schedulerEntry: Entry'),
                            function(schedule, '    var schedulerEntry: SchedulerRegistryEntry'))
    source += '\nextension Schedule {\n' + next(line for line in schedule.splitlines() if 'static let allMonths:' in line) + '\n}\n'
    source = source.replace('extension Schedule.Action { static var turnOn: Self { .on } }', '')
    source = source.replace(function(source, 'struct Entry:'), '')
    source = source.replace('struct SchedulerActionSet { let index: UInt8; let entry: Entry }', '')
    source = source.replace('final class Element {', 'final class Element {\n    weak var schedulerModel: Model?\n    func contains(modelWithSigModelId: Int) -> Bool { true }\n    func model(withSigModelId: Int) -> Model? { schedulerModel }\n')
    source = source.replace('        schedulerSetupModels.forEach { allSchedulerModelEntrys[$0] = [:] }',
                            '        schedulerSetupModels.forEach { allSchedulerModelEntrys[$0] = [:]; $0.parentElement?.schedulerModel = $0 }')
    source = source.replace('    var respondAddresss: [Address] = []', '''    var respondAddresss: [Address] = []
    var notRespondAddresss: [Address] = []
    // PRODUCTION_FINISHED''')
    proxy = (lib / 'Manager/MeshProxyMessageCommand.swift').read_text()
    source = source.replace('// PRODUCTION_FINISHED', function(proxy, '    var isFinished: Bool'))
    source = source.replace(function(source, 'final class MeshProxyMessageCommand'), '// LIFECYCLE_PROXY')
    source = source.replace(function(source, 'final class MeshLibManager'), '')
    # Keep the same SQLite schema/bootstrap; run only the joined boundary scenarios.
    main = function(source, '    static func main()')
    source = source.replace(main, '''    static func main() throws {
        let path = CommandLine.arguments[1]
        SunSmartDataManager.shared.db = try Connection(path)
        Schedule.initDatabase()
        try schedulerLifecycle(path: path)
    }''')
    source += '''
public protocol StaticMeshResponse {}
public protocol StaticAcknowledgedMeshMessage {}
extension Int {
    static var schedulerSetupServerModelId: Int { 0x1201 }
    static var genericOnOffServerModelId: Int { 0x1000 }
    static var lightLightnessServerModelId: Int { 0x1300 }
    static var lightLCServerModelId: Int { 0x130F }
}
extension SchedulerAction {
    static var on: Self { .turnOn }; static var off: Self { .turnOff }; static var scene: Self { .sceneRecall }
}
extension SchedulerRegistryEntry: Equatable {
    init(isValid: Bool, sceneNumber: UInt16 = 0, enabled: Bool = true) {
        if !isValid { self.init(); return }
        self.init(year: enabled ? .any() : .specific(year: 0), month: .any(of: [.January]), day: .any(),
                  hour: .specific(hour: 8), minute: .specific(minute: 0), second: .specific(second: 0),
                  dayOfWeek: .any(of: [.Monday]), action: .turnOn, transitionTime: .unknown, sceneNumber: sceneNumber)
    }
}
'''
    for path in ['Type Extensions/Data.swift', 'Mesh Model/StepResolution.swift', 'Mesh Model/TransitionTime.swift',
                 'Mesh Messages/SchedulerMessage.swift']:
        source += '\n' + (base / path).read_text()
    for name in ['SchedulerGet', 'SchedulerStatus', 'SchedulerActionGet', 'SchedulerActionSet', 'SchedulerActionStatus']:
        source += '\n' + (base / f'Mesh Messages/Time and Scenes/{name}.swift').read_text()
    source += '\npublic extension SchedulerRegistryEntry' + (lib / 'Manager/MeshScheduleServer.swift').read_text().split('public extension SchedulerRegistryEntry')[1]
    source += '\n' + (lib / 'Manager/MeshSchedulerObservation.swift').read_text()
    network = (base / 'Layers/NetworkManager.swift').read_text()
    source += '\nenum NetworkManager {\n' + function(network, '    static func schedulerResponseMatches(') + '\n}\n'
    node = (lib / 'Node/Node+Messages.swift').read_text()
    ack = node[node.index('        case is SchedulerStatus:'):node.index('        case is TimeStatus:')]
    source += '''
extension Node {
    var elements: [Element] { schedulerSetupModels.compactMap(\\.parentElement) }
    func rebuildSchedulerActions() { rebuildTimedSchedulerActions() }
    func observe(_ message: MeshMessage, source: Address) {
        switch message {
''' + ack + '''
        default: break
        }
    }
}
'''
    # Join actual SDK property serialization to SQLite instead of an always-true save.
    database = (lib / 'MeshDatabase.swift').read_text()
    saving = database[database.index('        var modelSchedulerContainers:'):database.index('        let lightLCPropertysData', database.index('        var modelSchedulerContainers:'))]
    loading_start = database.index('                switch SchedulerModelCachePersistence.decode(schedulersData)')
    loading = database[loading_start:database.index('\n            }\n            \n            if let data = row[PropertyExpressionKey.lightLCPropertys]', loading_start)]
    source = source.replace('    let uuid = UUID()', '    var uuid = UUID()')
    source = source.replace('    var propertiesSaveSucceeds = true', '    var propertiesSaveSucceeds = true\n    var corruptedSchedulerModelActionsData: Data?\n    var schedulerModelCacheDecodeError: String?')
    source = source.replace('    @discardableResult func savePropertys() -> Bool { propertiesSaveSucceeds }', '''
    @discardableResult func savePropertys() -> Bool {
        guard propertiesSaveSucceeds else { return false }
        do {
            let data = saveSnapshotProperty()
            try SunSmartDataManager.shared.db!.run("INSERT OR REPLACE INTO fixture_node_properties VALUES (?, ?)", uuid.uuidString, Blob(bytes: Array(data)))
            return true
        } catch { return false }
    }
    func reloadProperties() throws {
        let blob = try SunSmartDataManager.shared.db!.scalar("SELECT cache FROM fixture_node_properties WHERE uuid = ?", uuid.uuidString) as! Blob
        loadSnapshotProperty(Data(blob.bytes))
    }
''')
    source = source.replace('        Schedule.initDatabase()', '        Schedule.initDatabase()\n        try SunSmartDataManager.shared.db!.execute("CREATE TABLE fixture_node_properties (uuid TEXT PRIMARY KEY, cache BLOB)")')
    source += '\n' + (lib / 'Node/SchedulerModelCachePersistence.swift').read_text()
    source += '\nextension Node {\nfunc saveSnapshotProperty() -> Data {\n' + saving + '\nreturn allSchedulersData!\n}\nfunc loadSnapshotProperty(_ schedulersData: Data) {\n' + loading + '\n}\n'
    source += '''func element(withAddress address: UInt16) -> Element? { elements.first { $0.unicastAddress == address } }
'''
    exports = (root / 'SunSmart/Common/Data/ExportData.swift').read_text()
    source += function(exports, '    func restoreLocalSchedulerObservation(') + '\n}\n'
    fixture = (root / 'Tests/Timed/TimedSchedulerLifecycleTests.swift').read_text()
    fixture = fixture.replace('// PRODUCTION_SUBMISSION', function(proxy, '    private final class Submission'))
    fixture = fixture.replace('// PRODUCTION_COMPLETION', '\n'.join(function(proxy, marker) for marker in [
        '    private func reportSuccess(', '    private func finishMessages()', '    private func reset()']))
    return source.replace('// LIFECYCLE_PROXY', fixture)
