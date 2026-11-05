#!/usr/bin/env python3
"""Real App factory + SDK handles, TimeSet/Zone codecs and TAI conversion; network/UI are boundaries."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
sdk = (root / '.local-sdk/nordic-sig-mesh-sdk').resolve() / 'Sources/NordicSigMeshSDK'
manager = (sdk / 'MeshLib/Manager/MeshMessageManager.swift').read_text()
handle = manager[manager.index('public class MeshMessageHandle {'):]
factory = (root / 'SunSmart/Common/Data/SiteTimeSetMessageFactory.swift').read_text().replace('#if canImport(NordicSigMeshSDK)', '').replace('import NordicSigMeshSDK', '').replace('#endif', '')
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
public class Model { public var parentElement: Element? }
public class Element {
    public var unicastAddress: UInt16 = 1; public var parentNode: Node?
    func model(withSigModelId: UInt16) -> Model? { parentNode?.timeSetupModel }
}
public class Node {
    var network: Network?; var timeSetupModel: Model?
    static func setLocalTimeMessage(date: Date, timeZone: TimeZone) -> TimeSet { TimeSet(input: ExplicitTimeSetInput.make(date: date, timeZone: timeZone)) }
}
public class Network { var uuid = UUID(); var nodes: [Node] = [] }
class Key { var key = Data([1]); var index = 1; var networkId = Data([2]) }
class MeshLibManager { static let manager = MeshLibManager(); var isMeshNetworkConnected = true }
class MeshNetworkManager {
    static let instance = MeshNetworkManager()
    var meshNetwork: Network? = Network(); var currentNetworkKey = Key(); var currentApplicationKey = Key()
    var callback: ((Result<MeshMessage, Error>) -> Void)?
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
    @MainActor func prepareClock(storageValue: String?) async -> SiteTimeSetTimeZoneResolution? { SiteTimeSetMessageFactory.resolve(storageValue: storageValue) }
}
public class MeshSchedulerTask { var isCancelled = false }
class MeshSchedulerTransmission {}
class MeshGroupControlContext {}
class MessageHandle {}
// Response bookkeeping is the SDK Proxy/Fast Add boundary. Only a source-matched ACK marks success.
private var confirmed: Set<ObjectIdentifier> = []
extension MeshMessageHandle {
    var continuous: Bool { get { false } set {} }
    var isSuccessful: Bool { confirmed.contains(ObjectIdentifier(self)) && (transmissionIsValid?() ?? true) }
    func confirmMatchedResponse() { confirmed.insert(ObjectIdentifier(self)) }
}
'''
tests = r'''
import Foundation
@main struct Tests {
    static func check(_ ok: @autoclosure () -> Bool, _ reason: String) { if !ok() { fatalError(reason) } }
    static func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.04)) }
    static func main() throws {
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
        check(completed && MeshAPI.queued.count == 2 && MeshAPI.queued[1].prepareMessageForSend(), "TimeStatus completion must still permit the supplementary clear plan")
        network.nodes = []
        check(!MeshAPI.queued[1].prepareMessageForSend(), "Removed devices cannot receive a queued old plan")
        network.nodes = [node]; MeshAPI.queued.removeAll()
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
}
'''
with tempfile.TemporaryDirectory(prefix='site-clock-wire-') as directory:
    temp = Path(directory)
    (temp/'boundary.swift').write_text(stubs+'\n'+data+'\n'+handle)
    (temp/'factory.swift').write_text(factory)
    (temp/'tests.swift').write_text(tests)
    subprocess.run(['swiftc','-module-cache-path',str(temp/'modules'),'-parse-as-library',
        str(root/'SunSmart/Common/Data/SiteTimeZoneValue.swift'),str(temp/'boundary.swift'),
        *map(str,real),str(temp/'factory.swift'),str(temp/'tests.swift'),'-o',str(temp/'test')],check=True)
    subprocess.run([str(temp/'test')],check=True)
