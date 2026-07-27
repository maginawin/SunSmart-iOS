enum KineticSwitchProxyScanDecision: Equatable {
    case allowBinding
    case allowProxyTakeover
    case rejectExistingBinding
}

enum KineticSwitchProxySaveDecision<Address: Equatable>: Equatable {
    case unchanged
    case preserveCurrentForRemoval(Address)
    case replaceCurrent(pendingRemoval: Address)
    case rejectPendingRemovalConflict
}

enum KineticSwitchGroupMemberRemovalDecision: Equatable {
    case unaffected
    case markPendingRemoval
    case reusePendingRemoval
    case rejectPendingRemovalConflict
}

struct KineticSwitchProxyReferenceCleanupDecision: Equatable {
    let clearsCurrent: Bool
    let clearsPendingRemoval: Bool
    let clearsCredentials: Bool
}

enum KineticSwitchBindingPolicy {

    static func cleanupGroupAddresses<Address: Hashable>(
        active: [Address],
        pendingRemoval: [Address]
    ) -> [Address] {
        uniqueAddresses(active + pendingRemoval)
    }

    static func cleanupProxyAddresses<Address: Hashable>(
        current: Address?,
        pendingRemoval: Address?
    ) -> [Address] {
        uniqueAddresses([pendingRemoval, current].compactMap { $0 })
    }

    static func scanDecision<Address: Equatable>(
        detectedProxyAddress: Address?,
        selectedProxyAddress: Address?,
        ownedByAnotherSwitch: Bool
    ) -> KineticSwitchProxyScanDecision {
        guard let detectedProxyAddress else {
            return .allowBinding
        }
        guard !ownedByAnotherSwitch,
              detectedProxyAddress == selectedProxyAddress else {
            return .rejectExistingBinding
        }
        return .allowProxyTakeover
    }

    static func proxySaveDecision<Address: Equatable>(
        savedCurrent: Address?,
        pendingRemoval: Address?,
        requestedCurrent: Address?
    ) -> KineticSwitchProxySaveDecision<Address> {
        guard requestedCurrent != savedCurrent, let savedCurrent else {
            return .unchanged
        }
        if let pendingRemoval, pendingRemoval != savedCurrent {
            return .rejectPendingRemovalConflict
        }
        guard requestedCurrent != nil else {
            return .preserveCurrentForRemoval(savedCurrent)
        }
        return .replaceCurrent(pendingRemoval: savedCurrent)
    }

    static func shouldConfigureProxy<Address: Equatable>(
        current: Address?,
        pendingRemoval: Address?,
        isExitingGroup: Bool
    ) -> Bool {
        guard !isExitingGroup, let current else {
            return false
        }
        return current != pendingRemoval
    }

    static func groupMemberRemovalDecision<Address: Equatable>(
        node: Address,
        current: Address?,
        pendingRemoval: Address?
    ) -> KineticSwitchGroupMemberRemovalDecision {
        if current == node {
            guard let pendingRemoval else {
                return .markPendingRemoval
            }
            return pendingRemoval == node
                ? .reusePendingRemoval
                : .rejectPendingRemovalConflict
        }
        return pendingRemoval == node ? .reusePendingRemoval : .unaffected
    }

    static func referenceCleanupDecision<Address: Equatable>(
        node: Address,
        current: Address?,
        pendingRemoval: Address?
    ) -> KineticSwitchProxyReferenceCleanupDecision {
        let clearsCurrent = current == node
        return KineticSwitchProxyReferenceCleanupDecision(
            clearsCurrent: clearsCurrent,
            clearsPendingRemoval: pendingRemoval == node,
            clearsCredentials: clearsCurrent
        )
    }

    private static func uniqueAddresses<Address: Hashable>(
        _ addresses: [Address]
    ) -> [Address] {
        var seen: Set<Address> = []
        return addresses.filter { seen.insert($0).inserted }
    }
}
