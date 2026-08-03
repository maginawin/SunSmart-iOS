import Foundation

struct DeviceScheduleAddressCleanupResult<Address: Equatable> {
    let activeAddresses: [Address]
    let pendingDeleteAddresses: [Address]
    let didChange: Bool
}

enum DeviceScheduleAddressCleanup {
    static func removing<Address: Equatable>(
        address: Address,
        activeAddresses: [Address],
        pendingDeleteAddresses: [Address]
    ) -> DeviceScheduleAddressCleanupResult<Address> {
        let filteredActiveAddresses = activeAddresses.filter { $0 != address }
        let filteredPendingDeleteAddresses = pendingDeleteAddresses.filter { $0 != address }
        return DeviceScheduleAddressCleanupResult(
            activeAddresses: filteredActiveAddresses,
            pendingDeleteAddresses: filteredPendingDeleteAddresses,
            didChange: filteredActiveAddresses.count != activeAddresses.count
                || filteredPendingDeleteAddresses.count != pendingDeleteAddresses.count
        )
    }
}
