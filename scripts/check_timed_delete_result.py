#!/usr/bin/env python3
"""Run the production Timed delete batch with failed reservation/empty messages."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'SunSmart/Main/Timed/Model/ScheduleServer.swift').read_text()
start = source.index('    private static func runScheduleDeviceBatches(')
methods = source[start:source.rindex('\n}')]
fixture = r'''
import Foundation
final class Node {
    var cleared = false
    var timeModel: Model? = nil
    func applyMessageHandle(_ handle: MeshMessageHandle) { if !handle.ignoreReply { cleared = true } }
}
final class Element { let unicastAddress: UInt16 = 1 }
final class Model { var parentElement: Element? = Element() }
final class Group {}
final class MeshMessageHandle {
    var address: UInt16? = 1, model: Model? = nil
    var isSuccessful = true, continuous = true, ignoreReply = false
    var message = "delete"
}
final class Schedule {
    var enabled = false, failReservation = false, ignoreReply = false
    func slot(on node: Node) -> Int? { 0 }
    func deletionIsSynchronized(on node: Node) -> Bool { node.cleared }
    func needsSync(on node: Node, contextGroup: Group? = nil) -> Bool { !node.cleared }
    func getMessageHandles(node: Node, contextGroup: Group? = nil, delete: Bool = false) -> [MeshMessageHandle] {
        if failReservation { return [] }
        let handle = MeshMessageHandle(); handle.ignoreReply = ignoreReply
        return [handle]
    }
}
enum TimedSchedulerBindings {
    static func reserveForDeletion(schedule: Schedule, node: Node? = nil) -> Bool { !schedule.failReservation }
    static func reserveForSending(schedule: Schedule, node: Node, contextGroup: Group?) -> Bool { !schedule.failReservation }
}
enum SiteTimeSetMessageFactory { static func makeHandle(node: Node, model: Model) -> MeshMessageHandle? { MeshMessageHandle() } }
final class MeshNetworkManager {
    static let instance = MeshNetworkManager()
    final class Network { let node = Node(); func node(withAddress address: UInt16) -> Node? { node } }
    let meshNetwork: Network? = Network()
}
final class MeshProxyMessageCommand {
    static let shared = MeshProxyMessageCommand()
    func addMessage(messageHandles: [MeshMessageHandle], progressBack: ((Int) -> Void)?,
        successfulBack: (MeshMessageHandle, Int) -> Void, failedBack: (MeshMessageHandle) -> Void,
        finishedBack: ([MeshMessageHandle]) -> Void) {
        messageHandles.forEach { successfulBack($0, 0) }
        finishedBack(messageHandles)
    }
}
struct ScheduleServer {
    private struct ScheduleDeviceBatch { let node: Node; let contextGroup: Group?; let delete: Bool }
    static func run(_ schedule: Schedule) -> Bool {
        let node = MeshNetworkManager.instance.meshNetwork!.node
        var failure = false
        runScheduleDeviceBatches([.init(node: node, contextGroup: nil, delete: true)], schedule: schedule,
            index: 0, hadFailure: false) { failure = $0 }
        return failure
    }
METHODS
}
@main struct Run {
    static func main() {
        let schedule = Schedule()
        schedule.failReservation = true
        precondition(ScheduleServer.run(schedule), "failed reservation cannot become a successful empty deletion")
        schedule.failReservation = false
        schedule.ignoreReply = true
        precondition(ScheduleServer.run(schedule), "ACK without confirmed clearing cannot remove the business record")
        schedule.ignoreReply = false
        precondition(!ScheduleServer.run(schedule))
        print("PASS: production deletion batch preserves records on reservation failure or stale reply, completes verified clearing")
    }
}
'''.replace('METHODS', methods)
with tempfile.TemporaryDirectory(prefix='timed-delete-') as directory:
    path = Path(directory)
    (path / 'Harness.swift').write_text(fixture)
    subprocess.run(['swiftc', '-parse-as-library', str(root / 'SunSmart/Common/Data/TimedScheduleTimeSyncPolicy.swift'),
                    str(path / 'Harness.swift'), '-o', str(path / 'Tests')], check=True)
    subprocess.run([str(path / 'Tests')], check=True)
