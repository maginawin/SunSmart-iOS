import Foundation
typealias Address = UInt16

// Only the top-level input/output boundary is substituted. The entire production
// .group branch is inserted below; real device diff builders have their own suite.
final class Node: Equatable {
    let primaryUnicastAddress: UInt16
    var pending = true
    init(_ address: UInt16) { primaryUnicastAddress = address }
    static func == (lhs: Node, rhs: Node) -> Bool { lhs === rhs }
}
struct Group { var nodes: [Node] }
struct NodeSyncData {}
struct GroupProfileSyncContext {
    enum Reason { case memberAdded, edited }
    let reason: Reason
}
final class Device { let node: Node; init(_ node: Node) { self.node = node } }
final class Section { var devices: [Device] = [] }
struct ProfileSensorProtectionContext {
    func preDisableDeviceModel() -> Device? { nil }
    func postTargetStateDeviceModel() -> Device? { nil }
}
final class EmergencyBuilder {
    var adding: [Node] = [], exiting: [Node] = []
    func appendEmergencyFireControllerGroupMutationItems(to: Section, group: Group, addNodes: [Node], exitNodes: [Node]) {
        adding = addNodes; exiting = exitNodes
    }
}
struct ProximityBuilder {
    func appendProximityLightingItems(to: Section, datas: [(node: Node, syncData: NodeSyncData)], title: String) {}
}
extension String { var localizedString: String { self } }
final class PlanProbe {
    var groupProfileSyncContext: GroupProfileSyncContext? = nil
    let profileSensorProtectionContext: ProfileSensorProtectionContext? = nil
    let supplementaryProximityLightingSyncDatas: [(node: Node, syncData: NodeSyncData)] = []
    let emergencyBuilder = EmergencyBuilder(), proximityBuilder = ProximityBuilder()
    var counts: [Int] = []
    var contexts: [GroupProfileSyncContext.Reason?] = []
    func getSyncDeviceModel(group: Group, node: Node, effectiveMemberCount: Int,
                            profileSyncContext: GroupProfileSyncContext? = nil) -> (removeDevice: Device?, configturationDevice: Device?) {
        counts.append(effectiveMemberCount); contexts.append(profileSyncContext?.reason)
        return node.pending ? (Device(node), Device(node)) : (nil, nil)
    }
    func build(group: Group, inNodes: [Node]?, outNodes: [Node]?) -> (remove: [Device], configure: [Device]) {
        let removeSection = Section(), configurationSection = Section()
        // PRODUCTION_GROUP_PLAN
        return (removeSection.devices, configurationSection.devices)
    }
}
func check(_ value: Bool, _ reason: String) {
    guard value else { fputs("FAIL: \(reason)\n", stderr); exit(1) }
}
func addresses(_ devices: [Device]) -> [UInt16] { devices.map { $0.node.primaryUnicastAddress } }
let l1 = Node(0x49F9), l2 = Node(0x5010), old = Node(0x5020)
let first = PlanProbe()
let initial = first.build(group: Group(nodes: [old]), inNodes: [l1], outNodes: [])
check(addresses(initial.configure) == [0x49F9, 0x5020] && first.counts == [2, 2], "First addition includes new and retained members exactly once")
check(first.contexts.first! == .memberAdded, "New member retains Profile context")
for _ in 0..<3 {
    // Represents partial subscription ACK followed by same-page retry/re-entry.
    let retry = PlanProbe()
    let result = retry.build(group: Group(nodes: [l1, old]), inNodes: [l1], outNodes: [])
    check(addresses(result.configure) == [0x49F9, 0x5020], "Partial membership/retry must not duplicate L1 configuration")
    check(addresses(result.remove) == [0x49F9, 0x5020], "Each legitimate removal stage is retained once")
    check(retry.counts == [2, 2], "Effective member count must equal the union")
}
let duplicate = PlanProbe()
let aliases = duplicate.build(group: Group(nodes: [l1, old, old]), inNodes: [l1, Node(0x49F9), l2, l2], outNodes: [old, Node(0x5020), l2])
check(addresses(aliases.configure) == [0x49F9], "Stable identity de-duplicates aliases and exit wins over add")
check(Set(addresses(aliases.remove)) == [0x49F9, 0x5010, 0x5020] && aliases.remove.count == 3, "Exit/config removal stages each retain one owner")
check(duplicate.counts.allSatisfy { $0 == 1 }, "Exited members do not inflate Profile count")
check(duplicate.emergencyBuilder.adding.map(\.primaryUnicastAddress) == [0x49F9]
      && duplicate.emergencyBuilder.exiting.map(\.primaryUnicastAddress) == [0x5020, 0x5010], "Emergency mutation receives normalized membership")
let ordinary = PlanProbe(); ordinary.groupProfileSyncContext = .init(reason: .edited)
check(ordinary.build(group: Group(nodes: [l1, old]), inNodes: nil, outNodes: nil).configure.count == 2, "Ordinary group sync retains members")
check(ordinary.contexts.allSatisfy { $0 == .edited }, "Ordinary Profile edit keeps its context")
l1.pending = false
let done = PlanProbe().build(group: Group(nodes: [l1]), inNodes: [l1], outNodes: [])
check(done.configure.isEmpty && done.remove.isEmpty, "Planner preserves no-work results from device diff generation")
check(PlanProbe().build(group: Group(nodes: []), inNodes: [], outNodes: []).configure.isEmpty, "Empty group is legal")
print("PASS: production Group planning: first add, partial membership/retry, stable identity, exit precedence, count/Profile, emergency normalization and empty/no-work results")
