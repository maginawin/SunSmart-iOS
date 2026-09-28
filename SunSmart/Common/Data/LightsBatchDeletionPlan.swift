import Foundation

/// Immutable, credential-free snapshot. Includes hidden nodes and every known
/// receiver of the selected Space AppKey, including its associated Gateway.
struct LightsBatchDeletionPlan {
    struct Node {
        let id: String
        let address: UInt16
        let vendorAddress: UInt16?
        let businessGroup: UInt16?
        let subscriptions: Set<UInt16>
        let groupStateKnown: Bool
    }
    struct Task {
        let destination: UInt16
        let members: Set<String>
        let repetitions: Int
        var isUnicast: Bool { destination < 0x8000 }
        var followingGap: TimeInterval { isUnicast ? 0.2 : 1 }
    }
    let selected: Set<String>
    let tasks: [Task]
    let unsendable: Set<String>

    static func make(nodes: [Node], selected: Set<String>, allowBroadcast: Bool,
                     proxyID: String?) -> Self {
        let eligible = nodes.filter { selected.contains($0.id) && $0.vendorAddress != nil }
        let eligibleIDs = Set(eligible.map(\.id))
        if allowBroadcast, !selected.isEmpty, Set(nodes.map(\.id)).isSubset(of: selected),
           nodes.allSatisfy({ $0.groupStateKnown && $0.vendorAddress == $0.address }),
           selected == eligibleIDs {
            return .init(selected: selected, tasks: [.init(destination: 0xFFFF, members: selected, repetitions: 3)],
                         unsendable: [])
        }
        var tasks: [Task] = []
        var assigned = Set<String>()
        for group in Set(nodes.compactMap(\.businessGroup)).sorted() where group >= 0xC000 && group < 0xFF00 {
            let businessMembers = nodes.filter { $0.businessGroup == group }
            // A stale subscription outside this logical group can still receive
            // its command (including an unselected Proxy). Unknown means unicast.
            guard nodes.allSatisfy(\.groupStateKnown), businessMembers.allSatisfy({ selected.contains($0.id) && $0.groupStateKnown }) else { continue }
            let receivers = nodes.filter { $0.subscriptions.contains(group) }
            let receiverIDs = Set(receivers.map(\.id))
            guard receivers.count > 1, receiverIDs.isSubset(of: eligibleIDs),
                  receiverIDs.isDisjoint(with: assigned),
                  receivers.allSatisfy({ $0.groupStateKnown }) else { continue }
            tasks.append(.init(destination: group, members: receiverIDs, repetitions: 2))
            assigned.formUnion(receiverIDs)
        }
        for node in eligible where !assigned.contains(node.id) {
            tasks.append(.init(destination: node.vendorAddress!, members: [node.id], repetitions: 1))
            assigned.insert(node.id)
        }
        // Stable partition: the entire task that can actually reach Proxy goes last.
        if let proxyID {
            tasks = tasks.filter { !$0.members.contains(proxyID) } + tasks.filter { $0.members.contains(proxyID) }
        }
        return .init(selected: selected, tasks: tasks, unsendable: selected.subtracting(assigned))
    }
}
