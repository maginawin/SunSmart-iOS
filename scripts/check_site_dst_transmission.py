#!/usr/bin/env python3
"""Exercise the real SDK handle preparation immediately before serialization; models are boundary stubs."""
from pathlib import Path
import subprocess,tempfile,sys
root=Path(__file__).resolve().parents[1]
sdk=(root/'.local-sdk/nordic-sig-mesh-sdk').resolve()
manager=(sdk/'Sources/NordicSigMeshSDK/MeshLib/Manager/MeshMessageManager.swift').read_text()
handle=manager[manager.index('public class MeshMessageHandle {'):]
def method(source, marker):
 start=source.index(marker); end=source.index('{',start)+1; depth=1
 while depth:
  depth += (source[end]=='{')-(source[end]=='}'); end+=1
 return source[start:end].replace('private func','func',1)
normal=method(manager,'    private func sendMessageEvent()')
fast_source=(sdk/'Sources/NordicSigMeshSDK/MeshLib/Manager/MeshFastAddDeviceManager.swift').read_text()
fast=method(fast_source,'    private func sendAppendMessages(')
refresh=next((sdk/'Sources').rglob('RefreshableValue.swift')).read_text()
stubs='''import Foundation
public protocol MeshMessage {}
public class Model { public var parentElement: Element?; let schedulerObservation = SchedulerObservation() }
// Unrelated scheduler paths remain inactive for these TimeSet boundary tests.
public protocol MeshResponse: MeshMessage {}
public class MeshSchedulerTask { var isCancelled = false }
class MeshSchedulerTransmission {}
class SchedulerObservation { func sent(_ message: MeshMessage, owner: Int?) {} }
public class Element { public var unicastAddress: UInt16 = 1 }
public typealias Address = UInt16
public class MessageHandle {}
class MeshGroupControlContext { var owner = Owner() }; class Owner { func deliver(_ h: MeshMessageHandle) {} }
struct Packet: AcknowledgedMeshMessage { let offset: Int }
'''
stubs += r"""
protocol AcknowledgedConfigMessage: MeshMessage {}
protocol AcknowledgedMeshMessage: MeshMessage {}
protocol UnacknowledgedMeshMessage: MeshMessage {}
struct MeshAddress { let value: UInt16; init(_ value: UInt16) { self.value=value } }
final class Mutex { func sync(_ block: () -> Void) { block() } }
final class Node { var primaryUnicastAddress: UInt16 = 1 }
final class Network { func node(withAddress: UInt16) -> Node? { Node() } }
final class MeshLibManager { static let manager = MeshLibManager(); var currentProxy: Int? = 1 }
enum AccessError: Error { case modelNotBoundToAppKey }
struct ConfigModelAppBind: AcknowledgedConfigMessage { init?(applicationKey: Int, to: Model) {} }
final class MeshNetworkManager {
 static let instance = MeshNetworkManager()
 var currentApplicationKey = 0
 var meshNetwork: Network? = Network()
 var wire: [Int] = []
 func record(_ message: MeshMessage, completion: (Result<Int, Error>) -> Void) {
  if let packet=message as? Packet { wire.append(packet.offset) }; completion(.success(1))
 }
 func send(_ message: AcknowledgedConfigMessage, to: UInt16, withTtl: UInt8?, completion: (Result<Int, Error>) -> Void) throws { record(message,completion:completion) }
 func send(_ message: MeshMessage, to: MeshAddress, withTtl: UInt8?, using: Int, completion: (Result<Int, Error>) -> Void) throws { record(message,completion:completion) }
 func send(_ message: MeshMessage, to: Model, withTtl: UInt8?, completion: (Result<Int, Error>) -> Void) throws { record(message,completion:completion) }
}
"""
stubs += 'final class NormalSender { var mutex=Mutex(); var messages: [MeshMessageHandle]=[]; func sendSchedulerMessage(_ handle: MeshMessageHandle) { fatalError("Unexpected scheduler task in TimeSet fixture") }; func stopMessageTimer() {}; func handleSendResult<T>(_ result: Result<T,Error>, messageHandle: MeshMessageHandle) {}\n' + normal + '\n}\n'
stubs += r"""final class FastSender {
 var appendPreparationID: UUID?
 var appendMessages: [MeshMessageHandle]=[]
 var configMessageHandles: [MeshMessageHandle]=[]
 var device=(address: UInt16(1), other: 0)
 var wire: [Int]=[]
 var failed=0, active=true
 func deviceAddSuccessHandle() {}
 func isCurrentMessage(_ handle: MeshMessageHandle) -> Bool { active && appendMessages.first === handle }
 func failCurrentAppendMessageAndContinueOrFinish() { failed += 1; appendMessages=[] }
 func sendConfigNodeMessages() {}
 func sendMessage(_ h: MeshMessageHandle, toAddress: UInt16, node: Node) throws { if let p=h.message as? Packet { wire.append(p.offset) } }
 func sendMessage(_ h: MeshMessageHandle, toModel: Model) throws { if let p=h.message as? Packet { wire.append(p.offset) } }
""" + fast + '\n}\n'
test='''
import Foundation
@main struct Tests {
 static func check(_ value: Bool, _ message: String) { if !value { fatalError(message) } }
 static func main() {
  var offset = -300, valid = false, generations = 0, completions = 0
  var release: ((Bool) -> Void)?
  let handle = MeshMessageHandle(messageProvider: { generations += 1; return Packet(offset: offset) }, address: 1)
  handle.prepareForTransmission = { release = $0 }
  handle.transmissionIsValid = { valid }
  handle.prepareTransmission { ok in check(ok, "Resolved prerequisite permits sending"); completions += 1 }
  check(completions == 0, "Wire preparation must wait for API completion")
  valid = true; release?(true); release?(true)
  check(completions == 1, "Duplicate provider completion must not duplicate a send")
  check(handle.prepareMessageForSend(), "Ready snapshot sends")
  check((handle.message as? Packet)?.offset == -300, "Prepared packet uses resolved offset")
  let prior = generations
  valid = false; offset = -360
  check(!handle.prepareMessageForSend(), "Crossing next_switch after queueing rejects serialization")
  check(generations == prior, "Rejected message must not generate an old or guessed packet")
  handle.prepareTransmission { ok in check(!ok, "Failed refresh rejects transmission"); completions += 1 }
  release?(false)
  check(completions == 2, "Failure settles exactly once")
  let sender = NormalSender()
  var rejected=0
  handle.transmissionRejected = { rejected += 1 }
  sender.messages=[handle]; sender.sendMessageEvent()
  check(rejected == 1 && MeshNetworkManager.instance.wire.isEmpty, "Real normal queue rejects an expired message")
  valid=true
  handle.transmissionOwnerIsCurrent = { false }
  sender.messages=[handle]; sender.sendMessageEvent()
  check(rejected == 2 && MeshNetworkManager.instance.wire.isEmpty, "A cancelled queue owner cannot send")
  handle.transmissionOwnerIsCurrent = { true }
  sender.messages=[handle]; sender.sendMessageEvent()
  check(MeshNetworkManager.instance.wire == [-360], "Actual queued send refreshes the wire packet")
  for cancel in [false, true] {
   let fast = FastSender()
   valid=true
   fast.appendMessages=[handle]
   fast.sendAppendMessages()
   check(fast.wire.isEmpty, "Fast Add waits for async prerequisite")
   release?(true)
   if cancel { fast.active=false } else { valid=false }
   RunLoop.main.run(until: Date().addingTimeInterval(0.03))
   check(fast.wire.isEmpty, "Real Fast Add cannot send after cancellation or post-preparation expiry")
   check(cancel || fast.failed == 1, "Expired Fast Add settles as failure")
  }
  let fast = FastSender(); valid=true
  fast.appendMessages=[handle]; fast.sendAppendMessages(); release?(true)
  RunLoop.main.run(until: Date().addingTimeInterval(0.03))
  check(fast.wire == [-360], "Real Fast Add sends only a prepared current packet")
  print("Site DST SDK handle, normal queue and Fast Add transmission boundaries passed")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='dst-transmission-') as temp:
 t=Path(temp);(t/'sdk.swift').write_text(stubs+'\n'+refresh+'\n'+handle);(t/'tests.swift').write_text(test)
 subprocess.run(['swiftc','-module-cache-path',str(t/'modules'),'-parse-as-library',str(t/'sdk.swift'),str(t/'tests.swift'),'-o',str(t/'tests')],check=True)
 subprocess.run([str(t/'tests')],check=True)
