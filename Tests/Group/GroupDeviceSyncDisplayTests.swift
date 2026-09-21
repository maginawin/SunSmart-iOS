import Foundation

extension NodeSyncStatusRefreshTests {
    static func groupDeviceSyncReadTests() async {
        let network = fixture(490), session = NSObject(), button = NSObject()
        let owners = network.nodes.map { _ in NSObject() }
        NodeSyncStatusRefresh.beginSession(owner: session)
        defer {
            NodeSyncStatusRefresh.endSession(owner: session)
            Node.perNodeDelay = 0; Node.onCheck = nil
            AppPerformance.observe(nil)
        }
        network.nodes[0].deviceOnlyNeedSync = true
        Node.perNodeDelay = 0.0001 // Make overlapping requests span multiple slices.
        Node.onCheck = { _ in require(NodeSyncReadContext.current != nil, "Group icon computed without shared context") }
        var reads = 0, completed = 0
        AppPerformance.observe { sample in
            if sample.name == "ProtectionFileRead" {
                require(!sample.main, "Group icon read protection on main")
                reads += 1
            }
        }
        for (node, owner) in zip(network.nodes, owners) {
            NodeSyncStatusRefresh.requestGroupData(node: node, owner: owner) { value in
                require(!value, "Group icon inherited device-only initialization status")
                completed += 1
            }
        }
        NodeSyncStatusRefresh.request(group: network.groups[0], owner: button) { value in
            require(!value, "Members button inherited device-only status"); completed += 1
        }
        require(network.nodes.allSatisfy { $0.checks == 0 }, "request performed synchronous node work")
        await drain { completed == 491 }
        require(network.nodes.allSatisfy { $0.checks == 1 } && reads == 2,
                "Group icons/button multiplied checks or protection reads")
        var deviceDone = false
        NodeSyncStatusRefresh.request(nodes: [network.nodes[0]], owner: button) { value in
            require(value, "device-only fixture did not differ from Group status"); deviceDone = true
        }
        await drain { deviceDone }
        require(network.nodes[0].checks == 1 && reads == 2, "device result was not shared")

        // An offline member still contributes to the Members button's Group result.
        let node = network.nodes[0]
        node.state = false; node.proximityLightingEnabled.toggle()
        NodeSyncStatusGeneration.invalidate()
        var groupDone = false
        NodeSyncStatusRefresh.request(group: network.groups[0], owner: button) { value in
            require(value, "Members ignored an offline unsynchronized member"); groupDone = true
        }
        await drain { groupDone }
        Node.perNodeDelay = 0

        let state = GroupSyncDisplayState()
        var changes = 0
        state.refresh(node: node) { changes += 1 }
        state.cancel()
        state.refresh(node: network.nodes[1]) { changes += 1 }
        await drain { changes == 1 }
        require(state.needsSync(for: node) == nil && state.needsSync(for: network.nodes[1]) == false,
                "replaced owner retained old node status")
        NodeSyncStatusGeneration.invalidate()
        require(state.needsSync(for: network.nodes[1]) == nil, "invalid revision remained synchronized")
        var changedDuringRead = false
        Node.onCheck = { checked in
            if checked === network.nodes[1], !changedDuringRead {
                changedDuringRead = true
                checked.proximityLightingEnabled.toggle()
                NodeSyncStatusGeneration.invalidate()
            }
        }
        state.refresh(node: network.nodes[1]) { changes += 1 }
        await drain { changes == 2 }
        require(state.needsSync(for: network.nodes[1]) == true, "in-flight invalidation published old Group result")
        Node.onCheck = nil

        let empty = Group(0xC002); empty.network = network; network.groups.append(empty)
        NodeSyncStatusGeneration.invalidate()
        state.refresh(group: empty) { changes += 1 }
        await drain { changes == 3 }
        require(state.needsSync(for: empty) == false, "empty Group lost synchronized state")
        SpaceData.current!.triggerZonesLoadFailed = true
        NodeSyncStatusGeneration.invalidate()
        state.refresh(group: empty) { changes += 1 }
        await drain { changes == 4 }
        require(state.needsSync(for: empty) == true, "unavailable Group result appeared synchronized")
        SpaceData.current!.triggerZonesLoadFailed = false

        var retained: GroupSyncDisplayState? = GroupSyncDisplayState()
        weak var released = retained
        retained?.refresh(node: node) { fatalError("released display owner received callback") }
        retained = nil
        require(released == nil, "Group request retained display owner")
        print("PASS: Group icons + Members button: 490 nodes/491 readers, 490 checks/2 worker protection reads; group-only semantics, offline, empty, unavailable, replacement/invalidation/cancel")
    }
}

#if os(macOS)
// Execute the production icon/button, visibility and cancellation functions.
// UIKit image/collection objects and ordinary device appearance are value sinks.
private final class DevicesViewCell: UICollectionViewCell {
    let iconImageView = ImageView()
    var device: Node!
    var selection = true, brightness = 75
    func bind(_ node: Node) {
        cancelGroupSyncStatus()
        device = node
        iconImageView.image = UIImage(named: !node.state ? "offline" :
            (node.isKeybindComplete ? node.elControllerLightsIconName : "device_repair"))
    }
    // PRODUCTION_DEVICE_SYNC
}
private final class GroupButtonSink {
    var hidden = false, updates = 0
    func setSyncButtonHidden(_ value: Bool) { hidden = value; updates += 1 }
}
private final class GroupMembersViewController: UIViewController {
    var isSyncPageVisible = true, isAddDevices = false
    let groupSyncDisplay = GroupSyncDisplayState(), functionView = GroupButtonSink()
    let collectionView = UICollectionView()
    var group: Group
    init(_ group: Group) { self.group = group }
    func refresh() { refreshVisibleGroupSyncStatus() }
    // PRODUCTION_MEMBERS_SYNC
    // PRODUCTION_MEMBERS_DISPLAY
}
private let groupDataUpdateNotificationName = "test-group-update"
private final class GroupViewController: UIViewController {
    var isSyncPageVisible = true
    let collectionView = UICollectionView()
    var group: Group
    init(_ group: Group) { self.group = group }
    func stopUIRefreshTimer() {}
    func refresh() { refreshVisibleGroupSyncStatus() }
    // PRODUCTION_DETAIL_SYNC
    // PRODUCTION_DETAIL_DISAPPEAR
    // PRODUCTION_DETAIL_DISPLAY
}

extension NodeSyncStatusRefreshTests {
    static func groupDeviceSyncDisplayTests() async {
        let network = fixture(3), session = NSObject(), marker = NSObject()
        NodeSyncStatusRefresh.beginSession(owner: session)
        defer { NodeSyncStatusRefresh.endSession(owner: session) }
        let node = network.nodes[0], replacement = network.nodes[1]
        node.deviceOnlyNeedSync = true
        let cell = DevicesViewCell(), page = GroupMembersViewController(network.groups[0])
        let detail = GroupViewController(network.groups[0])
        page.collectionView.visibleCells = [cell]; detail.collectionView.visibleCells = [cell]
        cell.bind(node); page.refresh()
        require(!page.functionView.hidden && cell.iconImageView.image == UIImage(named: node.unsyncIconName),
                "pending Group read appeared synchronized")
        await drain { page.functionView.hidden && cell.iconImageView.image == UIImage(named: node.elControllerLightsIconName) }
        require(cell.selection && cell.brightness == 75, "sync callback changed selection or brightness")
        let checks = node.checks
        for _ in 0..<20 { page.refresh() }
        require(node.checks == checks && page.functionView.hidden, "unchanged Group display repeated calculation")

        node.proximityLightingEnabled.toggle(); NodeSyncStatusGeneration.invalidate()
        page.refresh()
        await drain { page.groupSyncDisplay.needsSync(for: page.group) == true }
        require(!page.functionView.hidden, "Members hid pending Group after configuration changed")

        // Cancellation on scrolling and replacement must reject old icon writes.
        cell.prepareForReuse(); cell.bind(replacement)
        page.collectionView(page.collectionView, willDisplay: cell, forItemAt: IndexPath(index: 1))
        await drain { cell.iconImageView.image == UIImage(named: replacement.elControllerLightsIconName) }
        NodeSyncStatusGeneration.invalidate()
        cell.bind(node)
        detail.collectionView(detail.collectionView, willDisplay: cell, forItemAt: IndexPath(index: 0))
        detail.collectionView(detail.collectionView, didEndDisplaying: cell, forItemAt: IndexPath(index: 0))
        cell.bind(replacement)
        var done = false
        NodeSyncStatusRefresh.requestGroupData(node: node, owner: marker) { _ in done = true }
        await drain { done }
        require(cell.iconImageView.image == UIImage(named: replacement.elControllerLightsIconName),
                "offscreen old node overwrote rebound Cell")

        node.state = false; cell.bind(node); page.refresh(); detail.refresh()
        require(cell.iconImageView.image == UIImage(named: "offline"), "Group status overwrote offline icon")
        node.state = true; node.isKeybindComplete = false; cell.bind(node); page.refresh()
        require(cell.iconImageView.image == UIImage(named: "device_repair"), "Members replaced unbound repair icon")
        detail.refresh()
        await drain { cell.iconImageView.image == UIImage(named: node.unsyncIconName) }

        page.isAddDevices = true; page.refresh()
        require(page.functionView.hidden, "add-members mode displayed Sync button")
        page.isAddDevices = false; page.refresh()
        NodeSyncStatusGeneration.invalidate()
        replacement.proximityLightingEnabled.toggle()
        cell.bind(replacement); page.refresh()
        page.viewWillDisappear(false); detail.viewWillDisappear(false)
        let buttonUpdates = page.functionView.updates
        cell.iconImageView.image = UIImage(named: "hidden-sentinel")
        done = false
        NodeSyncStatusRefresh.requestGroupData(node: replacement, owner: marker) { _ in done = true }
        await drain { done }
        require(!page.isSyncPageVisible && !detail.isSyncPageVisible && page.functionView.updates == buttonUpdates
                && cell.iconImageView.image == UIImage(named: "hidden-sentinel"), "hidden page received icon/button callback")
        page.isSyncPageVisible = true; page.refresh()
        await drain { cell.iconImageView.image == UIImage(named: replacement.unsyncIconName) }
        require(!page.functionView.hidden, "reentry did not restore current Group status")
        print("PASS: production Group icon/Members button functions: online/offline/keybind, pending/normal, add mode, Cell reuse/scroll cancellation, hidden/reentry, live appearance preservation")
    }
}
#endif
