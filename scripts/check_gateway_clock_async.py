#!/usr/bin/env python3
"""Run the production coordinator with controlled transport callbacks (no BLE/UIKit)."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
source = (root/'SunSmart/Main/Device/Gateway/Model/GatewayDetailClockCoordinator.swift').read_text().replace('#if canImport(NordicSigMeshSDK)', '').replace('import NordicSigMeshSDK', '').replace('#endif', '')
stubs = r'''
import Foundation
struct ApplicationKey { var index = 0 }
class Model { var parentElement: Element?; var modelIdentifier = 0; var companyIdentifier: Int?; func isBoundTo(_ k: ApplicationKey) -> Bool { true } }
class Element { var unicastAddress = 1 }
class Node { var primaryUnicastAddress = 1; var timeModel: Model? = Model(); var timeSetupModel: Model? = Model(); var timestamp: UInt64 = 99; var timezone: TimeZone?; var applicationKeys = [ApplicationKey()]; func savePropertys() -> Bool { true } }
class Gateway { var lastUpdate: Int64 = 0; var lastUploadCloudTimestamp: Int64 = 0; var syncCloudError: String?; func save() -> Bool { true } }
struct GatewayInformationContext { var node = Node(); var gatewayModel = Gateway() }
extension InformationClockLease {
 static var held: Int { acquire(key: "fixture").map { $0.release(); return 0 } ?? 1 }
 static func acquire(node: Node) -> InformationClockLease? { acquire(key: "fixture") }
}

struct Ready { var nodeAddress = 1; var sessionID = UUID() }
class MeshLibManager { static let manager = MeshLibManager(); var currentProxyReadyContext: Ready? = Ready(); var currentProxy: Ready? = Ready() }
struct ConfigModelAppBind { init?(applicationKey: ApplicationKey, to: Model) {} }
struct ConfigModelAppStatus { enum Status { case success }; var status = Status.success; var applicationKeyIndex = 0; var elementAddress: Int?; var modelIdentifier = 0; var companyIdentifier: Int? }
class MeshNetworkManager { static let instance = MeshNetworkManager(); var meshNetwork: Int? = 1; var currentApplicationKey = ApplicationKey(); func send(_ message: ConfigModelAppBind, to: Node, completion: (Result<Any, Error>) -> Void) throws {} }
struct TimeGet {}
struct Clock { var seconds: UInt64; var subSecond: UInt8 = 0; var taiDelta: Int16 = 0; var tzOffset: TimeZone }
struct TimeStatus { var time: Clock }
class MeshAPI { static var replies: [(Any?) -> Void] = []; static func sendMessage(message: TimeGet, model: Model, timeout: Int, completion: @escaping (Any?) -> Void) { replies.append(completion) } }
struct Resolution {}
enum SiteTimeSetMessageFactory { static var reply: ((TimeStatus?) -> Void)?; static var valid: (() -> Bool)?; static func resolve(storageValue: String?) -> Resolution? { Resolution() }; static func sendPrepared(resolution: Resolution, model: Model, isCurrent: @escaping () -> Bool, completion: @escaping (TimeStatus?) -> Void) { valid = isCurrent; reply = completion } }
enum GatewayCloudSyncGenerationPolicy { static func next(now: Int64, current: Int64, uploaded: Int64) -> Int64 { now } }
class CloudSynchronizationManager { enum Operation { case syncGateway(gateway: Gateway, node: Node) }; enum Level { case promptly }; static let shared = CloudSynchronizationManager(); func addSynchronizationHandle(operation: Operation, level: Level) {} }
func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
func status(_ offset: Int) -> TimeStatus { TimeStatus(time: Clock(seconds: UInt64(Date().timeIntervalSince1970 - MeshTimeConversion.unixEpochOffset), tzOffset: TimeZone(secondsFromGMT: offset * 60)!)) }
@main struct Tests {
 static func main() {
  SiteDSTFixtures.install()
  let mode = CommandLine.arguments[1]
  let context = GatewayInformationContext()
  var clock = Date()
  let storage: String? = mode == "fallback" ? nil : "Asia/Singapore"
  if mode == "sync-change" {
   let snapshot = try! SiteTimeZoneSnapshot(identifier: "Asia/Singapore", response: ["code":200,"data":["is_dst":true,"current_offset":"UTC+08:00","next_switch":SiteTimeZoneSnapshot.requestDateString(clock.addingTimeInterval(60)),"switches_to":"UTC+07:30"]], requestedAt: clock)
   SiteTimeZoneValue.snapshotProvider = { _,_ in snapshot }
  }
  let coordinator = GatewayDetailClockCoordinator(context: context, targetProvider: {
   GatewayDetailTimeZoneResolver.resolve(storageValue: storage, at: clock)
  })
  let target = GatewayDetailTimeZoneResolver.resolve(storageValue: storage, at: clock)
  var successes = 0; var failures = 0; var offset: Int?
  if mode == "late" {
   assert(coordinator.read(target: target) { _ in successes += 100 })
   let oldReply = MeshAPI.replies.removeFirst()
   coordinator.cancelForDeletion()
   assert(coordinator.read(target: target) { if case .success = $0 { successes += 1 } })
   oldReply(status(0)); pump()
   assert(successes == 0 && InformationClockLease.held == 1, "late result cannot finish new operation")
   MeshAPI.replies.removeFirst()(status(480)); pump()
   assert(successes == 1)
  } else if mode == "queued" {
   assert(coordinator.synchronize(target: target) { _ in successes += 1 })
   let valid = SiteTimeSetMessageFactory.valid!
   let callback = SiteTimeSetMessageFactory.reply!
   coordinator.cancelForDeletion()
   assert(!valid(), "cancelled queued send must be rejected")
   callback(status(480)); pump()
   assert(successes == 0 && MeshAPI.replies.isEmpty)
  } else if mode == "failure" {
   assert(coordinator.read(target: target) { if case .failure = $0 { failures += 1 } })
   MeshAPI.replies.removeFirst()(nil); pump()
   assert(failures == 1 && context.node.timestamp == 99)
   assert(coordinator.synchronize(target: target) { if case .failure = $0 { failures += 1 } })
   SiteTimeSetMessageFactory.reply?(nil); pump()
   assert(failures == 2 && context.node.timestamp == 99)
  } else if mode == "fallback" || mode == "read-change" || mode == "exit" {
   assert(coordinator.read(target: target) { result in
    switch result { case .success(let value): successes += 1; offset = value.1; case .failure: failures += 1 }
   })
   if mode == "read-change" { SiteTimeZoneValue.snapshotProvider = { _, _ in nil } }
   if mode == "exit" { coordinator.finishPage(); assert(InformationClockLease.held == 0, "exit must release lease immediately") }
   MeshAPI.replies.removeFirst()(status(target.offsetMinutes!)); pump()
   if mode == "fallback" { assert(offset != nil, "read must use resolver phone fallback") }
   if mode == "read-change" { assert(successes == 0 && failures == 1, "changed read target must not publish success") }
   if mode == "exit" { assert(successes == 0) }
  } else {
   assert(coordinator.synchronize(target: target) { result in
    switch result { case .success: successes += 1; case .failure: failures += 1 }
   })
   assert(SiteTimeSetMessageFactory.valid?() == true)
   SiteTimeSetMessageFactory.reply?(status(480)); pump()
   if mode == "reconnect" { MeshLibManager.manager.currentProxyReadyContext = Ready() }
   if mode == "sync-change" { clock = clock.addingTimeInterval(61) }
   MeshAPI.replies.removeFirst()(status(480)); pump()
   if mode == "normal" { assert(successes == 1) }
   else { assert(successes == 0 && failures == 1, "stale final readback must fail") }
  }
  assert(InformationClockLease.held == 0)
  if mode == "read-change" || mode == "sync-change" || mode == "reconnect" {
   SiteDSTFixtures.install()
   let before = successes
   assert(coordinator.read(target: target) { if case .success = $0 { successes += 1 } })
   MeshAPI.replies.removeFirst()(status(480)); pump()
   assert(successes == before + 1, "failed operation must allow retry")
  }
  assert(InformationClockLease.held == 0)
  print("PASS coordinator \(mode)")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='gateway-clock-') as directory:
    path = Path(directory)
    lease = (root/'SunSmart/Main/Device/InformationClockRecovery.swift').read_text()
    lease = lease[lease.index('final class InformationClockLease {'):].split('#if canImport')[0]
    (path/'Coordinator.swift').write_text(source + '\n' + lease)
    (path/'Tests.swift').write_text(stubs)
    sdk = (root/'.local-sdk/nordic-sig-mesh-sdk').resolve()
    subprocess.run(['swiftc','-parse-as-library',str(root/'SunSmart/Common/Data/SiteTimeZoneValue.swift'),str(root/'Tests/Site/SiteDSTFixtures.swift'),str(sdk/'Sources/NordicSigMeshSDK/MeshLib/Message/MeshTimeConversion.swift'),str(path/'Coordinator.swift'),str(path/'Tests.swift'),'-o',str(path/'test')],check=True)
    failed = []
    for mode in ['fallback','read-change','exit','reconnect','sync-change','normal','late','failure','queued']:
        result = subprocess.run([str(path/'test'),mode],capture_output=True,text=True)
        print(result.stdout if result.returncode == 0 else mode + ': ' + result.stderr.splitlines()[0])
        if result.returncode: failed.append(mode)
    if failed: raise SystemExit('FAILED: ' + ', '.join(failed))
