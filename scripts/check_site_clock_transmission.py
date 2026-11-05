#!/usr/bin/env python3
"""Real App factory/service + SDK handles/codecs/GATT receipts; radio/API and PDU encryption are boundaries."""
from pathlib import Path
import subprocess, tempfile, sys
root = Path(__file__).resolve().parents[1]
sdk = (root / '.local-sdk/nordic-sig-mesh-sdk').resolve() / 'Sources/NordicSigMeshSDK'
manager = (sdk / 'MeshLib/Manager/MeshMessageManager.swift').read_text()
handle = manager[manager.index('public class MeshMessageHandle {'):]
factory = (root / 'SunSmart/Common/Data/SiteTimeSetMessageFactory.swift').read_text().replace('#if canImport(NordicSigMeshSDK)', '').replace('import NordicSigMeshSDK', '').replace('#endif', '')
def method(source, marker):
    start = source.index(marker)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end].replace('private func', 'func', 1)

service = (root / 'SunSmart/Main/Site/Model/SiteTimeZoneService.swift').read_text()
prepare_clock = method(service, '    @MainActor func prepareClock(storageValue:')
fast_source = (sdk / 'MeshLib/Manager/MeshFastAddDeviceManager.swift').read_text()
fast_send = method(fast_source, '    private func sendAppendMessages(')
initialization = (root / 'SunSmart/Main/Site/Model/GatewayFastAddTimeInitialization.swift').read_text().replace('#if canImport(NordicSigMeshSDK)', '').replace('import NordicSigMeshSDK', '').replace('#endif', '')
submission_source = (sdk / 'nRFMeshProvision/MeshNetworkManager+DeviceLeave.swift').read_text()
submission_receipt = method(submission_source, '        try await withCheckedThrowingContinuation')
timezone_submission = (sdk / 'nRFMeshProvision/MeshNetworkManager+TimeZoneSet.swift').read_text().replace('public extension', 'extension')
real_receipts = sdk / 'nRFMeshProvision/Bearer/GATT/GattWriteReceiptQueue.swift'

data = (sdk / 'nRFMeshProvision/Type Extensions/Data.swift').read_text()
data = data[data.index('extension UInt8 {'):data.index('// Source: http://stackoverflow.com/a/42241894')]
real = [sdk / 'MeshLib/Manager/RefreshableValue.swift', sdk / 'MeshLib/Message/MeshTimeConversion.swift',
        sdk / 'MeshLib/Message/ExplicitTimeSetInput.swift', sdk / 'nRFMeshProvision/Mesh Messages/TimeMessage.swift']
real += [sdk / ('nRFMeshProvision/Mesh Messages/Time and Scenes/' + n + '.swift') for n in ['TimeSet','TimeStatus','TimeZoneSet','TimeZoneStatus']]
stubs = r'''
import Foundation
public typealias Address = UInt16
extension UInt16 { static let allNodes: UInt16 = 0xffff; static let timeSetupServerModelId: UInt16 = 0x1201 }
public protocol MeshMessage { var parameters: Data? { get } }
public protocol MeshResponse: MeshMessage {}
public protocol StaticMeshResponse: MeshResponse { static var opCode: UInt32 { get } }
public protocol StaticAcknowledgedMeshMessage: MeshMessage { static var opCode: UInt32 { get }; static var responseType: StaticMeshResponse.Type { get } }
public class Model { public var parentElement: Element?; var bind = [1] }
public class Element {
    public var unicastAddress: UInt16 = 1; public var parentNode: Node?
    func model(withSigModelId: UInt16) -> Model? { parentNode?.timeSetupModel }
}
public class Node {
    var network: Network?; var timeSetupModel: Model?
    var primaryUnicastAddress: UInt16 = 1
    var timestamp: UInt64 = 0; var timezone: TimeZone?
    func savePropertys() -> Bool { true }
    static func setLocalTimeMessage(date: Date, timeZone: TimeZone) -> TimeSet { TimeSet(input: ExplicitTimeSetInput.make(date: date, timeZone: timeZone)) }
}
public class Network { var uuid = UUID(); var nodes: [Node] = []; func node(withAddress: UInt16) -> Node? { nodes.first } }
class Key { var key = Data([1]); var index = 1; var networkId = Data([2]) }
class MeshLibManager { static let manager = MeshLibManager(); var isMeshNetworkConnected = true }
class MeshNetworkManager {
    static let instance = MeshNetworkManager()
    var meshNetwork: Network? = Network(); var currentNetworkKey = Key(); var currentApplicationKey = Key()
    var callback: ((Result<MeshMessage, Error>) -> Void)?
    var deliveries: [((Result<Void, Error>) -> Void)] = []
    var transmitted: [Data] = []
    var failSend = false
    var managedProxyBearer: GattBearer? = GattBearer()
    var managedProxyIsReady = true
    @MainActor func submitUnsegmentedMessage(_ message: MeshMessage, to destination: Address,
        using applicationKey: Key, via bearer: GattBearer, isCurrent: @escaping () -> Bool) async throws {
        checkDestination = destination
        // Encryption is outside this boundary fixture; real TimeZoneSet bytes enter the real receipt queue.
        let pdu = (pdu: message.parameters!, unused: false)
        // SUBMISSION_RECEIPT
    }
    var checkDestination: UInt16?
    func waitFor(messageWithOpCode: UInt32, from: UInt16, timeout: TimeInterval, completion: @escaping (Result<MeshMessage, Error>) -> Void) throws { callback = completion }
}
class MeshAPI { static var queued: [MeshMessageHandle] = []; static func sendMessage(handle: MeshMessageHandle) { queued.append(handle) } }
class SiteData {
    static var stored: [String: SiteData] = [:]
    var timezone: String? = "America/Chicago"
    static func load(siteId: String) -> SiteData? { stored[siteId] }
}
enum UserData { static var currentServerRegion = 0; static var currentUserId = "test" }
class SiteTimeZoneService {
    static let shared = SiteTimeZoneService()
    var store = SiteTimeZoneStore(read: { _ in nil }, write: { _, _ in }, fetch: { _, _, completion in completion(.failure(NSError(domain: "offline", code: 1))) })
    // PREPARE_CLOCK
}
public class MeshSchedulerTask { var isCancelled = false }
class MeshSchedulerTransmission {}
class MeshGroupControlContext {}
class MessageHandle { func cancel() {} }
struct MeshAddress { let value: UInt16; init(_ value: UInt16) { self.value = value } }
enum AccessError: Error { case modelNotBoundToAppKey, invalidDestination }
enum BearerError: Error { case bearerClosed }
class GattBearer {
    let queue = GattWriteReceiptQueue()
    var isOpen = true
    @MainActor func sendTracked(_ data: Data, ofType: Int, canWrite: @escaping () -> Bool,
                                completion: @escaping (Bool) -> Void) throws -> UUID {
        let manager = MeshNetworkManager.instance
        if manager.failSend || !isOpen { throw BearerError.bearerClosed }
        let id = queue.append([Data(data.prefix(3)), Data(data.dropFirst(3))], canWrite: canWrite) { success in
            if success { manager.transmitted.append(data) }
            completion(success)
        }
        manager.deliveries.append { result in
            if case .failure = result { self.queue.cancel(id)?(); return }
            while self.queue.count > 0 { self.writeNext() }
        }
        return id
    }
    func writeNext() {
        guard let packet = queue.pop() else { return }
        guard queue.allowsWriting(packet) else { queue.cancel(packet.batch)?(); return }
        // The peripheral writeValue call is the hardware boundary.
        queue.didWrite(packet)?()
    }
    func cancelTracked(_ id: UUID) { queue.cancel(id)?() }
}
extension Int { static let networkPdu = 0 }
struct ConfigModelAppBind: MeshMessage {
    var parameters: Data? { nil }
    init?(applicationKey: Key, to: Model) {}
}
class FastSender {
    var appendPreparationID: UUID?
    var appendMessages: [MeshMessageHandle] = [], configMessageHandles: [MeshMessageHandle] = []
    var device = (address: UInt16(1), other: 0)
    var active = true, bearerOpen = true, failed = 0
    var wire: [Data] = []
    func deviceAddSuccessHandle() {}
    func isCurrentMessage(_ handle: MeshMessageHandle) -> Bool { active && appendMessages.first === handle }
    func failCurrentAppendMessageAndContinueOrFinish() { failed += 1; appendMessages = [] }
    func sendConfigNodeMessages() {}
    func sendMessage(_ handle: MeshMessageHandle, toAddress: UInt16, node: Node) throws {
        guard bearerOpen else { throw NSError(domain: "closed bearer", code: 1) }
        wire.append(handle.message.parameters!)
    }
    func sendMessage(_ handle: MeshMessageHandle, toModel: Model) throws {
        try sendMessage(handle, toAddress: device.address, node: toModel.parentElement!.parentNode!)
    }
    // FAST_SEND
}
// Response bookkeeping is the SDK Proxy/Fast Add boundary. Only a source-matched ACK marks success.
private var confirmed: Set<ObjectIdentifier> = []
extension MeshMessageHandle {
    var continuous: Bool { get { false } set {} }
    var isSuccessful: Bool { confirmed.contains(ObjectIdentifier(self)) && (transmissionIsValid?() ?? true) }
    func confirmMatchedResponse() { confirmed.insert(ObjectIdentifier(self)) }
}
'''
stubs = stubs.replace('// PREPARE_CLOCK', prepare_clock).replace('// FAST_SEND', fast_send).replace('// SUBMISSION_RECEIPT', submission_receipt)
tests = r'''
import Foundation
@main struct Tests {
    static func check(_ ok: @autoclosure () -> Bool, _ reason: String) { if !ok() { fputs("FAIL: \(reason)\n", stderr); exit(1) } }
    static func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.04)) }
    static func wait(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(3)
        while !condition() && Date() < deadline { pump() }
        check(condition(), "Async boundary timed out")
    }
    static func main() throws {
        if CommandLine.arguments.contains("cache") { try cacheRecovery(); return }
        let now = Date()
        var snapshot = try SiteTimeZoneSnapshot(identifier: "America/Chicago", response: ["code":200,"data":[
            "is_dst":false,"current_offset":"UTC-06:00","next_switch":"2030-01-01T00:00:00+00:00","switches_to":"UTC-05:00"]], requestedAt: now.addingTimeInterval(-10))
        SiteTimeZoneValue.snapshotProvider = { id, _ in id == snapshot.identifier ? snapshot : nil }
        let value = SiteTimeSetMessageFactory.resolve(storageValue: "America/Chicago")!
        let transition = SiteTimeSetMessageFactory.transitionMessage(resolution: value)!
        // 2030-01-01 UTC: 1893456000 - 946684800 + 37 = 946771237 Mesh TAI.
        check(transition.taiSeconds == 946771237, "Future TAI must use the SDK epoch and UTC delta, without adding a timezone offset")
        check(transition.tzOffset.secondsFromGMT() == -18000, "Standard-time snapshot must still schedule the next DST")
        let decoded = TimeZoneSet(parameters: transition.parameters!)!
        check(decoded.taiSeconds == 946771237 && decoded.tzOffset.secondsFromGMT() == -18000, "Actual six-byte SDK serialization must round-trip")
        check(transition.parameters?.count == 6 && transition.parameters?.first == 0x2c, "Wire offset must be encoded in 15-minute units")
        var current = true, rejected = 0
        SiteTimeSetMessageFactory.broadcast(resolution: value, isCurrent: { current }, rejected: { rejected += 1 })
        check(MeshAPI.queued.count == 2, "Space must enqueue current time followed by the future plan")
        check(MeshAPI.queued[0].message is TimeSet && MeshAPI.queued[1].message is TimeZoneSet, "Message ordering is TimeSet then TimeZoneSet")
        check(MeshAPI.queued.allSatisfy { $0.address == 0xffff && $0.prepareMessageForSend() }, "Both messages target all nodes with valid wire prerequisites")
        current = false
        check(MeshAPI.queued.allSatisfy { !$0.prepareMessageForSend() }, "Leaving the Space rejects both queued messages")
        MeshAPI.queued.removeAll()
        let network = MeshNetworkManager.instance.meshNetwork!
        let site = SiteData(); SiteData.stored[network.uuid.uuidString] = site
        let node = Node(); node.network = network; network.nodes = [node]
        let model = Model(), element = Element(); element.parentNode = node; model.parentElement = element; node.timeSetupModel = model
        if CommandLine.arguments.contains("fast") { fastAdd(node: node, model: model, site: site); return }
        let plan = SiteTimeSetMessageFactory.makePlan(node: node, model: model)!
        check(plan.handle.prepareMessageForSend(), "Real handle serializes with the pinned Site offset")
        let status = TimeStatus(parameters: (plan.handle.message as! TimeSet).parameters!)!
        check(plan.handle.responseIsValid?(status) == true, "Valid TimeStatus may proceed to the SDK source check")
        pump(); check(MeshAPI.queued.isEmpty, "A validator call before source matching must not enqueue a transition")
        plan.handle.confirmMatchedResponse()
        _ = plan.handle.responseIsValid?(status); _ = plan.handle.responseIsValid?(status)
        pump(); check(MeshAPI.queued.count == 1 && MeshAPI.queued.first?.message is TimeZoneSet, "One accepted TimeStatus adds one supplementary transition")
        MeshNetworkManager.instance.currentApplicationKey.key = Data([9])
        check(!MeshAPI.queued[0].prepareMessageForSend(), "AppKey changes reject an old supplementary plan")
        MeshNetworkManager.instance.currentApplicationKey.key = Data([1]); MeshAPI.queued.removeAll()
        site.timezone = nil
        let phone = SiteTimeSetMessageFactory.resolve(storageValue: "")!
        check(phone.storageValue == nil, "Empty Gateway target must match a missing Site timezone")
        var completed = false
        SiteTimeSetMessageFactory.sendPrepared(resolution: phone, model: model, isCurrent: { true }) { response in completed = response != nil }
        check(MeshAPI.queued.count == 1 && MeshAPI.queued[0].prepareMessageForSend(), "Gateway missing timezone must actually reach the wire")
        let phoneStatus = TimeStatus(parameters: (MeshAPI.queued[0].message as! TimeSet).parameters!)!
        MeshNetworkManager.instance.callback?(.success(phoneStatus)); pump()
        check(!completed, "Gateway must retain its connection until supplementary transmission completes")
        check(MeshNetworkManager.instance.deliveries.count == 1 && MeshAPI.queued.count == 1,
              "Supplementary plan must reach SDK delivery, not remain in the ordinary queue")
        MeshNetworkManager.instance.managedProxyBearer!.writeNext(); pump()
        check(!completed, "First GATT fragment cannot release the Gateway while another fragment is queued")
        MeshNetworkManager.instance.callback?(.success(phoneStatus)); pump()
        check(MeshNetworkManager.instance.deliveries.count == 1, "Late duplicate TimeStatus cannot duplicate the supplementary send")
        MeshNetworkManager.instance.deliveries.removeFirst()(.success(())); pump()
        check(completed && MeshNetworkManager.instance.transmitted.count == 1, "Delivery releases the Gateway without waiting for TimeZoneStatus")
        check(MeshNetworkManager.instance.checkDestination == element.unicastAddress, "Supplementary send targets the Time Setup element")
        MeshAPI.queued.removeAll()
        for failure in [false, true] {
            completed = false
            MeshNetworkManager.instance.failSend = failure
            SiteTimeSetMessageFactory.sendPrepared(resolution: phone, model: model, isCurrent: { true }) { response in completed = response != nil }
            check(MeshAPI.queued.last!.prepareMessageForSend(), "Retry TimeSet can send")
            MeshNetworkManager.instance.callback?(.success(phoneStatus)); pump()
            if !failure {
                check(!completed, "Async failure is pending until delivery settles")
                MeshNetworkManager.instance.deliveries.removeFirst()(.failure(NSError(domain: "send", code: 1))); pump()
            }
            check(completed, "Supplementary send failure cannot revoke TimeSet success")
            MeshAPI.queued.removeAll()
        }
        MeshNetworkManager.instance.failSend = false
        site.timezone = "America/Chicago"
        for scenario in ["future", "cancel", "removed", "missingSetup", "invalidStatus", "timeout"] {
            var active = true, settlements = 0
            let before = MeshNetworkManager.instance.transmitted.count
            var successful = false
            SiteTimeSetMessageFactory.sendPrepared(resolution: value, model: model, isCurrent: { active }) { response in
                settlements += 1; successful = response != nil
                MeshLibManager.manager.isMeshNetworkConnected = false
            }
            check(MeshAPI.queued.last!.prepareMessageForSend(), "Gateway TimeSet prepares before its ACK")
            let ack = TimeStatus(parameters: (MeshAPI.queued.last!.message as! TimeSet).parameters!)!
            if scenario == "missingSetup" { node.timeSetupModel = nil }
            if scenario == "invalidStatus" { MeshNetworkManager.instance.callback?(.failure(NSError(domain: "no TimeStatus", code: 1))) }
            else { MeshNetworkManager.instance.callback?(.success(ack)) }
            pump()
            if ["future", "cancel", "removed", "timeout"].contains(scenario) {
                check(settlements == 0 && MeshLibManager.manager.isMeshNetworkConnected,
                      "Connection stays owned while the actual write is pending")
                if scenario == "cancel" { active = false }
                if scenario == "removed" { network.nodes = [] }
                if scenario == "timeout" {
                    RunLoop.main.run(until: Date().addingTimeInterval(5.1))
                    check(MeshNetworkManager.instance.managedProxyBearer!.queue.count == 0, "Timed out GATT work is removed")
                }
                MeshNetworkManager.instance.deliveries.removeFirst()(.success(())); pump()
            }
            check(settlements == 1, "Success, cancellation, timeout and missing model each settle exactly once")
            check(successful == (scenario != "invalidStatus"), "Supplementary failure preserves only a valid TimeStatus success")
            if scenario == "future" {
                check(MeshNetworkManager.instance.transmitted.last == transition.parameters,
                      "The real future DST plan must be submitted before the completion disconnects")
            } else {
                check(MeshNetworkManager.instance.transmitted.count == before, "Stale or unsupported supplementary plans must not write")
            }
            MeshNetworkManager.instance.callback?(.success(ack)); pump()
            check(settlements == 1, "Late ACK after release cannot settle twice")
            MeshAPI.queued.removeAll(); node.timeSetupModel = model; network.nodes = [node]
            MeshLibManager.manager.isMeshNetworkConnected = true
        }
        site.timezone = nil
        network.nodes = []
        check(!plan.handle.prepareMessageForSend(), "Removed nodes cannot send old plans")
        network.nodes = [node]
        check(phone.snapshot == nil, "Phone fallback never fabricates a Site response")
        let clear = SiteTimeSetMessageFactory.transitionMessage(resolution: phone)!
        check(clear.taiSeconds == 0 && clear.tzOffset == phone.timeZone, "Phone fallback clears the previous Site transition")
        snapshot = try SiteTimeZoneSnapshot(identifier: "America/Chicago", response: ["code":200,"data":[
            "is_dst":true,"current_offset":"UTC+11:00","next_switch":"2030-01-01T00:00:00+00:00","switches_to":"UTC+10:30"]], requestedAt: now.addingTimeInterval(-10))
        check(!plan.handle.prepareMessageForSend(), "Site configuration changes reject an existing handle")
        let halfHour = SiteTimeSetMessageFactory.resolve(storageValue: "America/Chicago")!
        check(SiteTimeSetMessageFactory.transitionMessage(resolution: halfHour)?.parameters?.first == 106, "Thirty-minute DST must not be rounded to an hour")
        check(SiteTimeSetMessageFactory.transitionMessage(resolution: halfHour, at: Date(timeIntervalSince1970: 1893456000)) == nil, "At the switch instant the old plan is invalid")
        snapshot = try SiteTimeZoneSnapshot(identifier: "America/Chicago", response: ["code":200,"data":[
            "is_dst":false,"current_offset":"UTC-06:00","next_switch":NSNull(),"switches_to":NSNull()]], requestedAt: now.addingTimeInterval(-10))
        let none = SiteTimeSetMessageFactory.resolve(storageValue: "America/Chicago")!
        check(SiteTimeSetMessageFactory.transitionMessage(resolution: none)?.taiSeconds == 0, "No upcoming transition clears a stale future plan")
        print("Site clock actual App factory / SDK codecs / wire handle tests passed")
    }
    static func fastAdd(node: Node, model: Model, site: SiteData) {
        MeshLibManager.manager.isMeshNetworkConnected = false
        let ordinary = SiteTimeSetMessageFactory.makePlan(node: node, model: model)!
        check(!ordinary.handle.prepareMessageForSend(), "Ordinary queue still requires its Proxy")
        for scenario in ["success", "cancel", "closed", "account", "network", "key", "site", "removed"] {
            let initialization = GatewayFastAddTimeInitialization.make(node: node, siteTimeZoneStorageValue: site.timezone)!
            let sender = FastSender(); sender.appendMessages = [initialization.handle]
            sender.sendAppendMessages()
            let originalNetwork = MeshNetworkManager.instance.meshNetwork
            switch scenario {
            case "cancel": sender.active = false
            case "closed": sender.bearerOpen = false
            case "account": UserData.currentUserId = "another"
            case "network": MeshNetworkManager.instance.meshNetwork = Network()
            case "key": MeshNetworkManager.instance.currentApplicationKey.key = Data([8])
            case "site": site.timezone = "Asia/Tokyo"
            case "removed": originalNetwork?.nodes = []
            default: break
            }
            if scenario == "cancel" { pump(); pump() }
            else { wait { !sender.wire.isEmpty || sender.failed > 0 } }
            if scenario == "success" {
                check(sender.wire.count == 1, "Fast Add must send through its own bearer while the global Proxy is disconnected")
                let sent = TimeSet(parameters: sender.wire[0])!
                node.timestamp = sent.time.seconds; node.timezone = sent.time.tzOffset
                check(initialization.acceptsCurrentNodeState(node), "Successful Fast Add must retain initialized Gateway time")
            } else {
                check(sender.wire.isEmpty, "Cancelled, disconnected or stale Fast Add cannot send: " + scenario)
            }
            UserData.currentUserId = "test"; MeshNetworkManager.instance.meshNetwork = originalNetwork
            MeshNetworkManager.instance.currentApplicationKey.key = Data([1]); site.timezone = "America/Chicago"
            originalNetwork?.nodes = [node]
        }
        print("Fast Add factory + real SDK append sender regressions passed")
    }
    static func cacheRecovery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = SiteTimeZoneCache(directory: directory)
        let identifier = "Future/ServerConfirmed"
        let now = Date()
        let snapshot = try SiteTimeZoneSnapshot(identifier: identifier, response: ["code":200,"data":[
            "is_dst":false,"current_offset":"UTC+05:45","next_switch":"2030-01-01T00:00:00Z","switches_to":"UTC+06:00"]], requestedAt: now.addingTimeInterval(-10))
        try cache.write(identifier, data: JSONEncoder().encode(SiteTimeZoneCache.Envelope(version: 1, snapshot: snapshot)))
        for expired in [false, true] {
            var reads = 0, requests = 0
            let store = SiteTimeZoneStore(read: { id in reads += 1; return try cache.read(id) }, write: cache.write) { _, _, completion in
                requests += 1; completion(.failure(NSError(domain: "offline", code: 1)))
            }
            SiteTimeZoneService.shared.store = store
            SiteTimeZoneValue.snapshotProvider = { id, _ in store.snapshot(for: id) }
            check(!SiteTimeZoneValue(storageValue: identifier)!.isRecognizedTimeZone, "Cold start has no in-memory evidence")
            var done = false; var resolution: SiteTimeSetTimeZoneResolution?
            Task { @MainActor in resolution = await SiteTimeZoneService.shared.prepareClock(storageValue: identifier); done = true }
            wait { done }
            check(reads == 1, "Cold clock preparation must read persisted evidence before classifying an unknown IANA")
            if expired {
                check(resolution == nil && requests == 1, "Expired server-confirmed identity must wait for refresh, never use phone fallback")
            } else {
                check(resolution?.source == .site && resolution?.offsetMinutes == 345 && resolution?.nextOffsetMinutes == 360,
                      "First cold call must restore the Site offset and next DST plan")
                check(requests == 0, "Fresh durable evidence must not require a server request")
            }
            let old = try SiteTimeZoneSnapshot(identifier: identifier, response: ["code":200,"data":[
                "is_dst":false,"current_offset":"UTC+05:45","next_switch":"2020-01-01T00:00:00Z","switches_to":"UTC+06:00"]], requestedAt: Date(timeIntervalSince1970: 1546300800))
            try cache.write(identifier, data: JSONEncoder().encode(SiteTimeZoneCache.Envelope(version: 1, snapshot: old)))
        }
        print("Cold service + real Codable/disk cache regressions passed")
    }

}
'''
with tempfile.TemporaryDirectory(prefix='site-clock-wire-') as directory:
    temp = Path(directory)
    (temp/'boundary.swift').write_text(stubs+'\n'+data+'\n'+handle)
    (temp/'factory.swift').write_text(factory + '\n' + initialization + '\n' + timezone_submission)
    (temp/'tests.swift').write_text(tests)
    subprocess.run(['swiftc','-module-cache-path',str(temp/'modules'),'-parse-as-library',
        str(root/'SunSmart/Common/Data/SiteTimeZoneValue.swift'),str(root/'SunSmart/Main/Site/Model/SiteTimeZoneStore.swift'),str(temp/'boundary.swift'),
        *map(str,real),str(real_receipts),str(temp/'factory.swift'),str(temp/'tests.swift'),'-o',str(temp/'test')],check=True)
    for scenario in (sys.argv[1:] or ['fast', 'cache', 'gateway']):
        subprocess.run([str(temp/'test'), scenario], check=True)
