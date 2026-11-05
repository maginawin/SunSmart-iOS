#!/usr/bin/env python3
"""Read-only demo verification using current App policies and SDK wire codecs.

No network, device, database or App build. Synthetic Device Keys exist in memory
only; the published JSON deliberately omits them. Run from any directory.
"""
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SDK = (ROOT / '.local-sdk/nordic-sig-mesh-sdk').resolve() / 'Sources/NordicSigMeshSDK'

def section(text, start, end):
    return text[text.index(start):text.index(end, text.index(start))]

wire = (SDK / 'nRFMeshProvision/Mesh Messages/SchedulerMessage.swift').read_text()
data = (SDK / 'nRFMeshProvision/Type Extensions/Data.swift').read_text()
data = data[:data.index('extension CBUUID')].replace('import CoreBluetooth', '')
entry_extension = (SDK / 'MeshLib/Manager/MeshScheduleServer.swift').read_text()
entry_extension = entry_extension[entry_extension.index('public extension SchedulerRegistryEntry {'):]
schedule = (ROOT / 'SunSmart/Main/Timed/Model/Scheduler.swift').read_text()
entry_property = section(schedule, '    var schedulerEntry: SchedulerRegistryEntry {', '\n    init(id:')
node_messages = (SDK / 'MeshLib/Node/Node+Messages.swift').read_text()
neutral_projection = section(node_messages, '    func rebuildSchedulerActions() {', '    /// 更新设备节点数据')
app_node = (ROOT / 'SunSmart/Common/Data/MeshNetwork+SunSmart.swift').read_text()
owner_projection = section(app_node, '    private func rebuildTimedSchedulerActions() {', '    /// 更新节点缓存数据').replace('private func', 'func', 1)

# Execute the reviewed local documentation example and compare its algorithms
# against the same fixtures that the production Swift/SDK verifier reads below.
document = (HERE.parent / '261105_1429_space_timed_json_contract.md').read_text()
reference = document.split('```python\n# SNAPSHOT_CODEC_REFERENCE\n', 1)[1].split('\n```', 1)[0]
codec = {'__name__': 'snapshot_codec_reference'}
exec(compile(reference, '<documented snapshot codec>', 'exec'), codec)
standalone = HERE / 'scheduler_snapshot_demo.py'
assert standalone.read_text().split('\n', 2)[2].strip() == reference.strip()
with tempfile.TemporaryDirectory(prefix='timed-python-only-') as temporary:
    result = subprocess.run([sys.executable, '-I', str(standalone)], cwd=temporary,
                            text=True, capture_output=True, check=True)
    generated = json.loads(result.stdout)
assert generated == codec['demo_node_fragment']()
assert generated == json.loads((HERE / 'scheduler_snapshot_generated.json').read_text())
single = document.split('```python\n# SINGLE_ENTRY_GENERATION_EXAMPLE\n', 1)[1].split('\n```', 1)[0]
exec(compile(single, '<documented single entry example>', 'exec'), {'__name__': 'single_entry_example'})
print('PASS: standalone Python example runs outside repository; generated JSON and documentation code match')
main_payload = json.loads((HERE / 'space_timed_v2_demo.json').read_text())
state_cases = json.loads((HERE / 'timed_state_cases.json').read_text())['cases']
wire_examples = json.loads((HERE / 'scheduler_wire_examples.json').read_text())['examples']
for example in wire_examples:
    decoded = codec['decode_entries'](example['entriesData'])
    assert codec['encode_entries'](decoded) == example['entriesData']
    slot, entry = next(iter(decoded.items()))
    assert codec['pack_entry'](slot, entry).hex().upper() == example['parametersHex']
    assert codec['readable_legacy'](slot, entry) == example['fields']
for payload in [main_payload] + [case['spaceFragment'] for case in state_cases]:
    for node in payload['nodes']:
        snapshot = node.get('custProps', {}).get('schedulerModelStates')
        if not isinstance(snapshot, dict):
            continue
        for encoded in [snapshot['legacyEntriesData']] + [m['entriesData'] for m in snapshot['models']]:
            assert codec['encode_entries'](codec['decode_entries'](encoded)) == encoded
        legacy = codec['decode_entries'](snapshot['legacyEntriesData'])
        assert [codec['readable_legacy'](slot, legacy[slot]) for slot in sorted(legacy)] == sorted(node['schedules'], key=lambda x: x['id'])
for node in main_payload['nodes']:
    snapshot = node['custProps']['schedulerModelStates']
    merged = codec['neutral_projection']([codec['decode_entries'](m['entriesData']) for m in snapshot['models']])
    assert codec['encode_entries'](merged) == snapshot['legacyEntriesData']
neutral_case = next(c for c in state_cases if c['case'] == 'same_slot_sdk_neutral_projection')
snapshot = neutral_case['spaceFragment']['nodes'][0]['custProps']['schedulerModelStates']
merged = codec['neutral_projection']([codec['decode_entries'](m['entriesData']) for m in snapshot['models']])
assert codec['encode_entries'](merged) == snapshot['legacyEntriesData']
assert codec['encode_entries']({}) == ''
assert codec['neutral_projection']([{0: codec['DEFAULT_CLEAR']}]) == {}
try:
    codec['encode_entries'](None)
except ValueError:
    pass
else:
    raise AssertionError('Unknown Model must not encode as empty')
print('PASS: documented Python codec matches all demo bytes and readable projections; empty/unknown distinction')

HARNESS = r'''
import Foundation
import CryptoKit
public typealias SceneNumber = UInt16
struct DemoScene { let number: UInt16 }
struct Schedule {
    static let allMonths: [Month] = [.January,.February,.March,.April,.May,.June,.July,.August,.September,.October,.November,.December]
    let enabled: Bool, action: SchedulerAction, fadeTime: Int, hour: Int, minute: Int
    let weekDays: [WeekDay], scene: DemoScene?
    init(_ s: [String: Any]) {
        enabled=s["enabled"] as! Bool; action=SchedulerAction(rawValue: UInt8(s["action"] as! Int))!
        fadeTime=s["fadeTime"] as! Int; hour=s["hour"] as! Int; minute=s["minute"] as! Int
        let mask=s["dayOfWeek"] as! Int
        weekDays=[WeekDay.Monday,.Tuesday,.Wednesday,.Thursday,.Friday,.Saturday,.Sunday].filter { mask & Int($0.rawValue) != 0 }
        scene=(s["sceneAddress"] as? String).flatMap { UInt16($0,radix:16) }.map { DemoScene(number:$0) }
    }
    // PRODUCTION_ENTRY_PROPERTY
}
enum DemoModel: Hashable { case ordinary, lightLC }
final class ProjectionNode {
    let schedulerSetupModels: [DemoModel] = [.ordinary, .lightLC]
    var allSchedulerModelEntrys: [DemoModel: [Int: SchedulerRegistryEntry]] = [:]
    var schedulerActions: [Int: SchedulerRegistryEntry] = [:]
    var scheduleIds: [Int] = []
    var schedules: [Int: Schedule] = [:]
    var automaticGroup = false
    func timedSchedule(at slot: Int) -> Schedule? { schedules[slot] }
    func schedulerSetupModel(for owner: TimedSchedulerOwner) -> DemoModel? {
        owner == .ordinary ? .ordinary : .lightLC
    }
    // PRODUCTION_NEUTRAL_PROJECTION
    // PRODUCTION_OWNER_PROJECTION
}
extension Schedule {
    // Node topology and Group lookup are fixture boundaries. The decision policy
    // and both cache reconstruction method bodies are production sources.
    static func schedulerModelOwner(for action: SchedulerAction, on node: ProjectionNode) -> TimedSchedulerOwner {
        TimedSchedulerOwnerPolicy.resolve(action:action == .turnOn ? .autoOn : .ordinary,
            membership:node.automaticGroup ? .automaticGroup : .noGroup)
    }
}
@main struct Verify {
    static func read(_ path: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [String: Any]
    }
    static func hydrate(_ fragment: [String: Any]) -> [String: Any] {
        var result=fragment
        result["nodes"]=(fragment["nodes"] as! [[String: Any]]).map { raw in
            var n=raw
            precondition(n["deviceKey"] == nil, "Published demos must omit Device Keys")
            let digest=SHA256.hash(data: Data(("timed-demo-only:" + (n["uuid"] as! String)).utf8))
            n["deviceKey"]=String(digest.map { String(format:"%02x",$0) }.joined().prefix(32)).uppercased()
            return n
        }
        return result
    }
    static func entries(_ data: Data) throws -> [Int: SchedulerRegistryEntry] {
        var values: [Int: SchedulerRegistryEntry]=[:]
        for bytes in try SchedulerModelSnapshot.entries(data) {
            let value=SchedulerRegistryEntry.unmarshal(bytes)
            precondition(SchedulerRegistryEntry.marshal(index:value.index,entry:value.entry)==bytes)
            values[Int(value.index)]=value.entry
        }
        return values
    }
    static func validate(_ source: [String: Any], expected: [String: Any]) throws {
        let p=hydrate(source)
        let canonical=TimedSchedulerPayloadPolicy.canonical(p)
        precondition((canonical != nil) == (expected["canonicalValid"] as? Bool ?? true))
        let n=(p["nodes"] as! [[String: Any]])
        let snapshotsValid=(try? n.forEach { node in
            if let snapshot=try SchedulerModelSnapshot.decode(node:node) {
                for model in snapshot.models { _ = try entries(model.entriesData) }
                _ = try entries(snapshot.legacyEntriesData)
            }
        }) != nil
        precondition(snapshotsValid == (expected["snapshotValid"] as? Bool ?? true))
        guard let canonical else { return }
        let c=try JSONSerialization.jsonObject(with:canonical) as! [String:Any]
        if let version=expected["canonicalSchema"] as? Int { precondition(c["timedSchemaVersion"] as? Int == version) }
        let schedules=c["schedules"] as! [[String:Any]]
        if let count=expected["canonicalBindingCount"] as? Int { precondition((schedules[0]["nodeSlots"] as! [Any]).count == count) }
        if let count=expected["canonicalDeviceCount"] as? Int { precondition((schedules[0]["deviceAddresses"] as! [Any]).count == count) }
        if expected["noGeneration"] as? Bool == true {
            precondition(!String(data:canonical,encoding:.utf8)!.contains("generation"))
        }
        _ = try SceneConfigurationPayload.records(payload:p)
        precondition(SpaceConfigurationIntegrityPolicy.scheduleTargetIssue(in:p) == nil)
        precondition(SpaceConfigurationIntegrityPolicy.profilesIssue(in:p) == nil)
        guard let s=schedules.first, let node=n.first, snapshotsValid else { return }
        let snapshot=try SchedulerModelSnapshot.decode(node:node)
        let address=Int(node["unicastAddress"] as! String,radix:16)!
        let slot=(s["nodeSlots"] as? [[String:Any]])?.first?["slot"] as? Int
        func modelEntries(_ address: Int) throws -> [Int:SchedulerRegistryEntry]? {
            try snapshot?.models.first { $0.elementAddress==String(format:"%04X",address) }.map { try entries($0.entriesData) }
        }
        if let difference=expected["syncDifference"] as? String {
            let actual: TimedSchedulerSyncDifference
            if (s["deviceAddresses"] as! [String]).isEmpty { actual = .notApplicable }
            else if let slot {
                let owner=try modelEntries(address), cleanup=try modelEntries(address+1)
                let ownerState: TimedSchedulerOwnerEntryState
                if let owner {
                    if let e=owner[slot] { ownerState=e == Schedule(s).schedulerEntry ? .matchingEntry : .mismatchingEntry }
                    else { ownerState = .missingEntry }
                } else { ownerState = .unknownModel }
                let cleanupState: TimedSchedulerCleanupEntryState = cleanup.map { $0[slot]?.isValid == true ? .residualEntry : .clearEntry } ?? .unknownModel
                actual=TimedSchedulerSyncPolicy.evaluate(ownerState:ownerState,cleanupStates:[cleanupState])
            } else { actual = .ownerEntryMissing }
            precondition(actual.rawValue==difference, "Expected \(difference), actual \(actual)")
        }
        if let cleared=expected["deletionCleared"] as? Bool {
            let actual=try [address,address+1].allSatisfy { address in
                guard let entries=try modelEntries(address), let slot else { return false }
                return entries[slot]?.isValid != true
            }
            precondition(actual==cleared)
        }
    }
    static func main() throws {
        let dir=CommandLine.arguments[1]
        let main=try read(dir+"/space_timed_v2_demo.json")
        try validate(main,expected:[:])
        var generatedNode=try read(dir+"/scheduler_snapshot_generated.json")
        // The server example returns only fields to merge into an existing Node.
        // Supply its synthetic Composition before full production validation.
        generatedNode["elements"]=(main["nodes"] as! [[String:Any]])[0]["elements"]
        try validate(["spaceData":["timedSchemaVersion":2], "nodes":[generatedNode],
            "schedules":[[String:Any]](), "groups":[[String:Any]](), "scenes":[[String:Any]]()],expected:[:])
        let mainNodes=hydrate(main)["nodes"] as! [[String:Any]]
        let mainSchedules=main["schedules"] as! [[String:Any]]
        // Validate the ordinary/LC placement and intentional partial result in
        // the main example, using the production owner policy and entry builder.
        for s in mainSchedules where [100,101,102,103,104,105,108,112].contains(s["id"] as! Int) {
            for binding in s["nodeSlots"] as! [[String:Any]] where binding["state"] as! String == "assigned" {
                let identity=binding["identity"] as! [String:Any]
                let node=mainNodes.first { $0["uuid"] as? String == identity["nodeUUID"] as? String }!
                let snapshot=try SchedulerModelSnapshot.decode(node:node)!
                let membership: TimedSchedulerMembership = node["groupAddress"] == nil ? .noGroup : .automaticGroup
                let owner=TimedSchedulerOwnerPolicy.resolve(action:s["action"] as! Int == 1 ? .autoOn : .ordinary,membership:membership)
                let primary=Int(node["unicastAddress"] as! String,radix:16)!
                let ownerAddress=String(format:"%04X",primary+(owner == .lightLC ? 1 : 0))
                let model=snapshot.models.first { $0.elementAddress==ownerAddress }!
                let slot=binding["slot"] as! Int
                let actual=try entries(model.entriesData)[slot]!
                let isIntentionalMismatch=s["id"] as! Int == 105 && primary == 0x0200
                precondition((actual == Schedule(s).schedulerEntry) != isIntentionalMismatch)
                for cleanup in snapshot.models where cleanup.elementAddress != ownerAddress {
                    let cleanupEntries = try entries(cleanup.entriesData)
                    precondition(cleanupEntries[slot]?.isValid != true)
                }
            }
        }
        let cases=try read(dir+"/timed_state_cases.json")["cases"] as! [[String:Any]]
        for c in cases { try validate(c["spaceFragment"] as! [String:Any],expected:c["expected"] as! [String:Any]) }
        let neutral=cases.first { $0["case"] as? String == "same_slot_sdk_neutral_projection" }!["spaceFragment"] as! [String:Any]
        let app=cases.first { $0["case"] as? String == "same_slot_app_owner_projection" }!["spaceFragment"] as! [String:Any]
        let neutralSnapshot=try SchedulerModelSnapshot.decode(node:(hydrate(neutral)["nodes"] as! [[String:Any]])[0])!
        let appSnapshot=try SchedulerModelSnapshot.decode(node:(hydrate(app)["nodes"] as! [[String:Any]])[0])!
        precondition(neutralSnapshot.models == appSnapshot.models)
        let projectionNode=ProjectionNode()
        projectionNode.allSchedulerModelEntrys=[.ordinary:try entries(neutralSnapshot.models[0].entriesData),
            .lightLC:try entries(neutralSnapshot.models[1].entriesData)]
        let original=projectionNode.allSchedulerModelEntrys
        projectionNode.schedules=[0:Schedule((neutral["schedules"] as! [[String:Any]])[0])]
        let neutralLegacy=try entries(neutralSnapshot.legacyEntriesData)
        let appLegacy=try entries(appSnapshot.legacyEntriesData)
        projectionNode.rebuildSchedulerActions()
        precondition(projectionNode.schedulerActions[0]! == neutralLegacy[0]!)
        projectionNode.rebuildTimedSchedulerActions()
        precondition(projectionNode.schedulerActions[0]! == appLegacy[0]!)
        precondition(Set(projectionNode.allSchedulerModelEntrys.keys) == Set(original.keys))
        for (model, oldEntries) in original {
            let current = projectionNode.allSchedulerModelEntrys[model]!
            precondition(Set(current.keys) == Set(oldEntries.keys))
            for (slot, oldEntry) in oldEntries { precondition(current[slot]! == oldEntry) }
        }
        projectionNode.automaticGroup=true
        projectionNode.rebuildTimedSchedulerActions()
        precondition(projectionNode.schedulerActions[0]! == neutralLegacy[0]!)
        projectionNode.automaticGroup=false
        projectionNode.allSchedulerModelEntrys[.ordinary]=[:]
        projectionNode.rebuildTimedSchedulerActions()
        precondition(projectionNode.schedulerActions.isEmpty)
        precondition(projectionNode.allSchedulerModelEntrys[.lightLC]?[0] != nil)
        let disabled=(cases.first { $0["case"] as? String == "disabled_synchronized" }!["spaceFragment"] as! [String:Any])["schedules"] as! [[String:Any]]
        let disabledEntry=Schedule(disabled[0]).schedulerEntry
        projectionNode.allSchedulerModelEntrys=[.ordinary:[0:disabledEntry],.lightLC:[1:SchedulerRegistryEntry()]]
        projectionNode.rebuildSchedulerActions()
        precondition(projectionNode.schedulerActions.count==1 && projectionNode.schedulerActions[0]! == disabledEntry)
        print("PASS: production SDK neutral and App owner projections; conflict, Owner change, residual, disabled and default-clear behavior")
        let examples=try read(dir+"/scheduler_wire_examples.json")["examples"] as! [[String:Any]]
        for example in examples {
            let bytes=Data(base64Encoded: example["entriesData"] as! String)!
            precondition(bytes.count==10)
            precondition(bytes.map { String(format:"%02X",$0) }.joined()==example["parametersHex"] as! String)
            let value=SchedulerRegistryEntry.unmarshal(bytes), e=value.entry
            precondition(SchedulerRegistryEntry.marshal(index:value.index,entry:e)==bytes)
            precondition(Int(e.transitionTime.rawValue)==example["transitionTimeRaw"] as! Int)
            let fields=example["fields"] as! [String:Int]
            let actual=["id":Int(value.index),"year":Int(e.year.value),"month":Int(e.month.value),"day":Int(e.day.value),
                "hour":Int(e.hour.value),"minute":Int(e.minute.value),"second":Int(e.second.value),"dayOfWeek":Int(e.dayOfWeek.value),
                "action":Int(e.action.rawValue),"transitionTime":Int(e.transitionTime.interval ?? 0),"sceneNumber":Int(e.sceneNumber)]
            precondition(fields==actual)
        }
        print("PASS: main Space fragment; \(cases.count) independent states; \(examples.count) SDK wire round-trips; production timed/snapshot/Scene validators")
    }
}
'''.replace('// PRODUCTION_ENTRY_PROPERTY', entry_property).replace('// PRODUCTION_NEUTRAL_PROJECTION', neutral_projection).replace('// PRODUCTION_OWNER_PROJECTION', owner_projection)

with tempfile.TemporaryDirectory(prefix='timed-json-demo-') as temporary:
    temporary = Path(temporary)
    harness = temporary / 'Harness.swift'
    harness.write_text(HARNESS + '\n' + wire + '\n' + data + '\n' + entry_extension)
    binary = temporary / 'Verify'
    env = dict(os.environ)
    cache = Path('/tmp/sunsmart-timed-json-demo-module-cache')
    cache.mkdir(exist_ok=True)
    env['CLANG_MODULE_CACHE_PATH'] = str(cache)
    env['SWIFT_MODULECACHE_PATH'] = str(cache)
    inputs = [
        ROOT / 'SunSmart/Common/Data/HDBConfiguration.swift',
        ROOT / 'SunSmart/Common/Data/HDBLightingZonePolicy.swift',
        ROOT / 'SunSmart/Main/Timed/Model/TimedSchedulerSlotPolicy.swift',
        ROOT / 'SunSmart/Main/Timed/Model/TimedSchedulerOwnerPolicy.swift',
        ROOT / 'SunSmart/Main/Scene/Model/SceneConfiguration.swift',
        ROOT / 'SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift',
        SDK / 'nRFMeshProvision/Mesh Model/StepResolution.swift',
        SDK / 'nRFMeshProvision/Mesh Model/TransitionTime.swift', harness]
    subprocess.run(['swiftc', '-parse-as-library', *map(str, inputs), '-o', str(binary)], check=True, env=env)
    subprocess.run([str(binary), str(HERE)], check=True, env=env)
