"""Execute production Sensor publication policy, planning and payload branches.

Uses value/model stubs and the current SDK's publication constructors and payload
encoding code. Covers profile planning, SDK publication construction and calibration
rollback, not the whole App, BLE, sampling or real asynchronous callback timing.
"""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
sdk = (repo / '.local-sdk/nordic-sig-mesh-sdk').resolve()
sync = (repo / 'SunSmart/Common/Data/Node+SyncData.swift').read_text()
handles = (repo / 'SunSmart/Common/Data/Node+MessageHandles.swift').read_text()
status = (repo / 'SunSmart/Main/Space/Model/SyncDevicesCellModel.swift').read_text()
page = (repo / 'SunSmart/Main/Group/Controller/GroupViewController.swift').read_text()
publish = (sdk / 'Sources/NordicSigMeshSDK/nRFMeshProvision/Mesh Model/Publish.swift').read_text()
config = (sdk / 'Sources/NordicSigMeshSDK/nRFMeshProvision/Mesh Messages/Foundation/Configuration/ConfigModelPublicationSet.swift').read_text()
resolution = (sdk / 'Sources/NordicSigMeshSDK/nRFMeshProvision/Mesh Model/StepResolution.swift').read_text()
sdk_lib = sdk / 'Sources/NordicSigMeshSDK/MeshLib'
calibration = (sdk_lib / 'Manager/MeshSensorCalibrateManager.swift').read_text()


def block(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    end, depth = opening + 1, 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


policy = sync[sync.index('enum SensorPublicationSyncMode {'):sync.index('/// 配置类型\nenum ProfileType {')]
group_policy = block(sync, '    func sensorServerPublicationRetransmit(')
planning_start = sync.index('        // 启用的传感器model', sync.index('    func getNodeSyncProfiles('))
planning = sync[planning_start:sync.index('            // 恢复光照校准值', planning_start)]
build_branch = handles[handles.index('        case .sensorEnabled(let sensorModels'):handles.index('        case .daylightCalibration(let value):')]
success_branch = status[status.index('        case .sensorEnabled(let sensorModels', status.index('    func isSuccessful(node: Node)')):status.index('        case .mode(let enabled):', status.index('    func isSuccessful(node: Node)'))]
page_branch = block(page, '        if let publishAmbientLightSensor = self.group.info.ambientLightSensorNode, let sensorModel = publishAmbientLightSensor.ambientLightSensorModel, sensorModel.publish?.publicationAddress != group.address {')


def sdk_publication_expression(path, variable):
    """Extract the executable construction, excluding commented legacy code."""
    prefix = f'let {variable} = ConfigModelPublicationSet'
    matches = [line.strip().split(' = ', 1)[1]
               for line in (sdk_lib / path).read_text().splitlines()
               if line.strip().startswith(prefix)]
    if len(matches) != 1:
        raise RuntimeError(f'Expected one publication construction: {path} / {variable}')
    return matches[0]


sdk_constructions = [
    ('calibration', 'Manager/MeshSensorCalibrateManager.swift', 'publishMessage', 'localNode.primaryUnicastAddress', '0'),
    ('node initialization', 'Node/Node+Messages.swift', 'publicationMessage', 'publishAddress', '0x40'),
    ('publish API', 'MeshAPI.swift', 'publicationMessage', 'publishAddress', '0x40 | UInt8(interval)'),
    ('legacy calibration', 'Manager/MeshSensorCalibrateServer.swift', 'publishMessage', 'localNode.primaryUnicastAddress', '0'),
    ('beta calibration', 'Manager/MeshSensorBetaCalibrateServer.swift', 'publishMessage', 'localNode.primaryUnicastAddress', '0'),
    ('legacy add', 'Manager/MeshAddDeviceManager.swift', 'publicationMessage', 'publishAddress', '0x40'),
    ('legacy periodic add', 'Manager/MeshAddDeviceManager.swift', 'publicationTimeMessage', 'publishAddress', '0x50'),
]

swift = r'''
import Foundation
typealias Address = UInt16
extension UInt16 {
    static let sensorServerModelId: UInt16 = 0x1100
    var isVirtual: Bool { (0x8000...0xBFFF).contains(self) }
}
struct MeshAddress: Equatable {
    let address: Address
    var hex: String { String(format: "%04X", address) }
    init(_ address: Address) { self.address = address }
    init?(hex: String) { guard let value = UInt16(hex, radix: 16) else { return nil }; address = value }
}
struct ApplicationKey { let index: UInt16 }
'''
swift += resolution[resolution.index('public enum StepResolution:'):]
swift += r'''
struct Publish: Equatable {
    let address: String
    var publicationAddress: MeshAddress { MeshAddress(hex: address)! }
    let index: UInt16
    let credentials: Int
    let ttl: UInt8
    let period: Period
    let retransmit: Retransmit
'''
swift += block(publish, '    public init(to destination: MeshAddress, using applicationKey: ApplicationKey,').replace('public ', '') + '\n'
swift += block(publish[publish.index('    /// This initializer for disabling publication'):], '    public init()').replace('public ', '') + '\n'
swift += r'''
    struct Period: Equatable {
        let numberOfSteps: UInt8
        let resolution: StepResolution
        let interval: TimeInterval
        static let disabled = Period()
'''
period = block(publish, '    public struct Period:')
for marker in ['        public init()', '        public init(_ interval:', '        public init(steps:']:
    swift += block(period, marker).replace('public ', '') + '\n'
swift += '\n}\n'
swift += block(publish, '    public struct Retransmit:') + '\n}\n'
swift += r'''
func + (lhs: Data, rhs: UInt16) -> Data { lhs + Data([UInt8(rhs & 0xFF), UInt8(rhs >> 8)]) }
func + (lhs: Data, rhs: UInt8) -> Data { lhs + Data([rhs]) }
func += (lhs: inout Data, rhs: UInt8) { lhs = lhs + rhs }
struct ConfigModelPublicationSet {
    let publish: Publish
    let elementAddress: Address
    let modelIdentifier: UInt16
    let companyIdentifier: UInt16?
'''
swift += block(config, '    public init?(_ publish:').replace('public ', '') + '\n'
swift += block(config, '    public init?(disablePublicationFor').replace('public ', '') + '\n'
swift += block(config, '    public var parameters: Data?') + '\n}\n'
swift += r'''
struct Element { let unicastAddress: Address? }
final class Model {
    var publish: Publish?
    let modelIdentifier: UInt16
    let companyIdentifier: UInt16? = nil
    let elementAddress: Address
    var parentElement: Element?
    init(_ element: Address, id: UInt16 = .sensorServerModelId) {
        elementAddress = element; modelIdentifier = id; parentElement = Element(unicastAddress: element)
    }
}
struct MeshMessageHandle { let message: ConfigModelPublicationSet; let address: Address }
struct MeshNetworkManager {
    static var instance = MeshNetworkManager()
    var currentApplicationKey = ApplicationKey(index: 0x123)
    var networkParameters = Parameters()
    struct Parameters { var defaultTtl: UInt8 = 5 }
}
enum Kind: CaseIterable { case occupancy, vacancy, occupancy_daylight, vacancy_daylight, daylight, manualControl, proximityLighting, proximityLightingWithPhotocell }
final class Profile { var type = Kind.occupancy }
final class Info { let profile = Profile(); var ambientLightSensorNode: Node? }
final class Group {
    let address = MeshAddress(0xC123)
    let info = Info()
    var nodes: [Node] = []
'''
swift += group_policy + '\n}\n'
swift += r'''
struct NodeSyncReadContext {
    static var current: NodeSyncReadContext?
    let count: Int
    func members(of group: Group) -> [Node] { Array(repeating: Node(), count: count) }
}
final class Node {
    let primaryUnicastAddress: Address
    init(_ address: Address = 0x0010) { primaryUnicastAddress = address }
    var defaultTTL: UInt8 = 15
    var presenceDetectedSensorModel: Model? = Model(0x0011)
    var ambientLightSensorModel: Model? = Model(0x0012)
    var syncReadGroup: Group?
    enum State { case inGroup }; let groupState = State.inGroup
    var sensorCalibrated = true
    struct Restore { var daylightCalibrationValue: Int?; var daylightCalibrationData: Int? }
    var restoreData: Restore?
    func publicationTasks(group: Group, effectiveMemberCount: Int?, sensorPublicationSyncMode: SensorPublicationSyncMode) -> [ProfileType] {
        let groupProfile = group.info.profile
        var syncProfile: [ProfileType] = []
'''
swift += planning + '\n        }\n        return syncProfile\n    }\n}\n'
swift += policy
swift += r'''
enum ProfileType {
    case sensorEnabled(sensorModels: [Model], publishAddress: Address, delay: TimeInterval = 0, retransmit: Publish.Retransmit = .disabled)
    case sensorDisable(sensorModels: [Model])
    func getMessageHandles(node: Node) -> [MeshMessageHandle] {
        var messageHandles: [MeshMessageHandle] = []
        switch self {
'''
swift += build_branch + '\n        }\n        return messageHandles\n    }\n'
swift += '    func isSuccessful(node: Node) -> Bool {\n        switch self {\n' + success_branch + '\n        }\n    }\n}\n'
swift += 'final class Page { let group = Group(); func appearancePublications() -> [MeshMessageHandle] {\n var messageHandles: [MeshMessageHandle] = []\n' + page_branch + '\n return messageHandles\n }\n}\n'
swift += r'''
var checks = 0
func require(_ condition: Bool, _ label: String) {
    checks += 1
    if !condition { print("FAIL: \(label)"); exit(1) }
}
func publication(_ group: Group, ttl: UInt8 = 0xFF, retransmit: Publish.Retransmit = .disabled, address: Address? = nil) -> Publish {
    Publish(to: MeshAddress(address ?? group.address.address), using: MeshNetworkManager.instance.currentApplicationKey,
            usingFriendshipMaterial: false, ttl: ttl, period: .disabled, retransmit: retransmit)
}
let g = Group(), n = Node()
g.nodes = [n]; g.info.ambientLightSensorNode = n
let model = n.presenceDetectedSensorModel!
for members in [1, 3, 4, 1000] {
    let target = g.sensorServerPublicationRetransmit(effectiveMemberCount: members)
    require(target.count == (members <= 3 ? 2 : 1) && target.interval == 100, "member-count retransmit boundary")
    for ttl: UInt8 in [0, 5, 15, 127, 255] {
        for retransmit in [target, .disabled] {
            model.publish = publication(g, ttl: ttl, retransmit: retransmit)
            require(model.isSensorServerPublicationConfigured(publishAddress: g.address.address, retransmit: target)
                    == (ttl == 255 && retransmit == target), "strict target")
            require(model.isSensorServerPublicationConfigured(publishAddress: g.address.address, retransmit: target, syncMode: .legacyCompatible)
                    == (ttl == 255), "legacy retransmit compatibility never ignores TTL")
        }
    }
    for kind in Kind.allCases {
        g.info.profile.type = kind
        let presence = [.occupancy, .vacancy, .occupancy_daylight, .vacancy_daylight].contains(kind)
        let ambient = [.occupancy_daylight, .vacancy_daylight, .daylight].contains(kind)
        for ttl: UInt8 in [5, 255] {
            n.presenceDetectedSensorModel?.publish = publication(g, ttl: ttl, retransmit: target)
            n.ambientLightSensorModel?.publish = publication(g, ttl: ttl, retransmit: target)
            let tasks = n.publicationTasks(group: g, effectiveMemberCount: members, sensorPublicationSyncMode: .strictTarget)
            let handles = tasks.flatMap { $0.getMessageHandles(node: n) }
            let enabled = handles.filter { $0.message.publish.publicationAddress.address != 0 }
            require(enabled.count == (ttl == 255 ? 0 : (presence ? 1 : 0) + (ambient ? 1 : 0)), "profile-specific publication repair")
            require(handles.filter { $0.message.publish.publicationAddress.address == 0 }.count
                    == (presence ? 0 : 1) + (ambient ? 0 : 1), "manual/proximity/daylight disable behavior preserved")
            for task in tasks {
                if case .sensorEnabled = task { require(!task.isSuccessful(node: n), "old TTL cannot be successful") }
            }
            for handle in enabled {
                let p = handle.message.publish, data = handle.message.parameters!
                require(p.ttl == 255 && p.index == 0x123 && p.credentials == 0 && p.period.numberOfSteps == 0, "publication fields")
                let e = handle.message.elementAddress
                require(Array(data) == [UInt8(e), 0, 0x23, 0xC1, 0x23, 0x01, 0xFF, 0, members <= 3 ? 0x0A : 0x09, 0, 0x11], "SDK SIG parameters preserve element, key and retransmit")
                let matching = [n.presenceDetectedSensorModel!, n.ambientLightSensorModel!].first { $0.elementAddress == e }!
                matching.publish = p
            }
            for task in tasks {
                if case .sensorEnabled = task { require(task.isSuccessful(node: n), "applied target succeeds") }
            }
            let again = n.publicationTasks(group: g, effectiveMemberCount: members, sensorPublicationSyncMode: .strictTarget)
            require(!again.contains { if case .sensorEnabled = $0 { return true }; return false }, "no repeated repair after success")
        }
    }
}
// Effective member count overrides context, which overrides the Group fallback.
NodeSyncReadContext.current = NodeSyncReadContext(count: 4)
require(g.sensorServerPublicationRetransmit().count == 1, "context member count")
require(g.sensorServerPublicationRetransmit(effectiveMemberCount: 3).count == 2, "explicit count takes priority")
NodeSyncReadContext.current = nil
require(g.sensorServerPublicationRetransmit().count == 2, "group fallback")
g.info.profile.type = .occupancy
for existing in [nil, publication(g, address: 0xC999)] {
    model.publish = existing
    require(!model.isSensorServerPublicationTargetConfigured(publishAddress: g.address.address), "absent/wrong address")
    require(n.publicationTasks(group: g, effectiveMemberCount: 4, sensorPublicationSyncMode: .legacyCompatible).contains {
        if case .sensorEnabled = $0 { return true }; return false
    }, "absent/wrong address produces task")
}
let wrongModel = Model(0x0013, id: 0x1000)
wrongModel.publish = publication(g)
require(!wrongModel.isSensorServerPublicationTargetConfigured(publishAddress: g.address.address), "non-Sensor model excluded")
for ttl: UInt8 in [5, 15, 127] {
    MeshNetworkManager.instance.networkParameters.defaultTtl = ttl; n.defaultTTL = ttl
    let task = ProfileType.sensorEnabled(sensorModels: [model], publishAddress: g.address.address, delay: 0, retransmit: .disabled)
    require(task.getMessageHandles(node: n).first!.message.publish.ttl == 255, "never copy App or node TTL")
}
let page = Page()
page.group.info.ambientLightSensorNode = n
n.ambientLightSensorModel?.publish = publication(page.group, ttl: 5)
require(page.appearancePublications().isEmpty, "page must not auto-migrate same-address legacy TTL")
n.ambientLightSensorModel?.publish = nil
let pageHandle = page.appearancePublications().first!
require(pageHandle.message.publish.ttl == 255 && pageHandle.message.publish.retransmit == .disabled, "page repair retains retransmit behavior")
'''
swift += r'''
func sdkPublications(node: Node, localNode: Node, publishAddress: Address, interval: Int)
    -> [(String, ConfigModelPublicationSet?, Address, UInt8)] {
    let manager = MeshNetworkManager.instance
    let currentAppkey = manager.currentApplicationKey
    let sensorModel = node.ambientLightSensorModel!
    let model = sensorModel
'''
utils = (sdk_lib / 'Utils/MeshUtils.swift').read_text()
swift += next(line for line in utils.splitlines() if line.startswith('public let TimeModelPublishInterval')).replace('public ', '') + '\n'
swift += '    return [\n'
for label, path, variable, target, period_byte in sdk_constructions:
    swift += f'        ("{label}", {sdk_publication_expression(path, variable)}, {target}, {period_byte}),\n'
swift += '    ]\n}\n'
swift += r'''
let sdkNode = Node(), phone = Node(0x0101)
for networkTTL: UInt8 in [5, 15, 127] {
    MeshNetworkManager.instance.networkParameters.defaultTtl = networkTTL
    for keyIndex: UInt16 in [0x123, 0xABC] {
        MeshNetworkManager.instance.currentApplicationKey = ApplicationKey(index: keyIndex)
        for interval in [0, 16, 63] {
            for destination: Address in [0xC123, 0xFFFF] {
                let results = sdkPublications(node: sdkNode, localNode: phone, publishAddress: destination, interval: interval)
                require(results.count == 7, "all seven SDK constructions execute")
                for (label, message, target, periodByte) in results {
                    require(message != nil, "\(label) builds publication")
                    let message = message!, p = message.publish
                    require(p.ttl == 0xFF, "\(label) must inherit device Default TTL, network TTL=\(networkTTL)")
                    require(p.publicationAddress.address == target && p.index == keyIndex && p.credentials == 0,
                            "\(label) preserves destination, AppKey and credentials")
                    require(p.retransmit == .disabled, "\(label) preserves retransmit")
                    let element = sdkNode.ambientLightSensorModel!.elementAddress
                    require(Array(message.parameters!) == [UInt8(element), 0, UInt8(target & 0xFF), UInt8(target >> 8),
                            UInt8(keyIndex & 0xFF), UInt8(keyIndex >> 8), 0xFF, periodByte, 0, 0, 0x11],
                            "\(label) encodes unchanged fields and period with TTL FF")
                }
            }
        }
    }
}

struct ConfigModelPublicationStatus { let isSuccess: Bool }
enum MeshAPI {
    static var sent: [(ConfigModelPublicationSet, Address)] = []
    static var response: ConfigModelPublicationStatus? = ConfigModelPublicationStatus(isSuccess: true)
    static func sendMessage(message: ConfigModelPublicationSet, address: Address) async -> Any? {
        sent.append((message, address))
        return response
    }
}
struct CalibrationRollback {
    var didModifyCalibration = true
    var sensorNode: Node?
    var previousSensorPublish: Publish?
'''
swift += block(calibration, '    private func restorePreviousPublicationIfNeeded()').replace('private func ', 'func ') + '\n}\n'
swift += r'''
for oldTTL: UInt8 in [0, 5, 15, 0xFF] {
    let old = Publish(to: MeshAddress(0xC789), using: ApplicationKey(index: 0xABC), usingFriendshipMaterial: true,
                      ttl: oldTTL, period: .init(steps: 7, resolution: .tensOfSeconds), retransmit: .init(3, timesWithInterval: 0.15))
    for snapshot in [nil, old] {
        for response in [nil, ConfigModelPublicationStatus(isSuccess: false), ConfigModelPublicationStatus(isSuccess: true)] {
            MeshAPI.sent = []; MeshAPI.response = response
            let restored = await CalibrationRollback(sensorNode: sdkNode, previousSensorPublish: snapshot).restorePreviousPublicationIfNeeded()
            require(restored == (response?.isSuccess == true), "SDK rollback reports success, rejection or missing response")
            require(MeshAPI.sent.count == 1 && MeshAPI.sent[0].1 == sdkNode.primaryUnicastAddress, "SDK rollback targets sensor node")
            let message = MeshAPI.sent[0].0
            if let snapshot {
                require(message.publish == snapshot, "SDK rollback preserves complete snapshot including old TTL")
                require(message.parameters![6] == oldTTL, "SDK rollback preserves old TTL on wire")
            } else {
                require(Array(message.parameters!) == [0x12, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x11],
                        "SDK rollback without snapshot disables publication with address and TTL zero")
            }
        }
    }
}
MeshAPI.sent = []
let untouched = await CalibrationRollback(didModifyCalibration: false).restorePreviousPublicationIfNeeded()
require(untouched && MeshAPI.sent.isEmpty, "unchanged calibration skips rollback")
let missingNode = await CalibrationRollback().restorePreviousPublicationIfNeeded()
require(!missingNode && MeshAPI.sent.isEmpty, "missing sensor cannot restore")
sdkNode.ambientLightSensorModel = nil
let missingModel = await CalibrationRollback(sensorNode: sdkNode).restorePreviousPublicationIfNeeded()
require(!missingModel && MeshAPI.sent.isEmpty, "missing model cannot restore")
sdkNode.ambientLightSensorModel = Model(0x12)
sdkNode.ambientLightSensorModel!.parentElement = nil
let missingElement = await CalibrationRollback(sensorNode: sdkNode).restorePreviousPublicationIfNeeded()
require(!missingElement && MeshAPI.sent.isEmpty, "invalid element cannot send disable publication")
print("PASS: \(checks) App/SDK publication behavior/payload assertions")
'''
with tempfile.TemporaryDirectory(prefix='sensor-publication-') as directory:
    source = Path(directory) / 'main.swift'
    source.write_text(swift)
    binary = Path(directory) / 'check'
    subprocess.run(['swiftc', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
