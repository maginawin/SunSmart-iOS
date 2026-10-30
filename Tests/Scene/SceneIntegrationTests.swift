import Foundation

@main struct SceneIntegrationTests {
    static func main() throws {
        identifyProductionIdentity()
        let manager = MeshNetworkManager.instance
        let a = Node(1), b = Node(2), u = Node(3), x = Node(4)
        let group = Group(); manager.groups = [group]
        manager.realNodes = [a, b, u, x]; a.group = group; x.group = group
        let scene = Scene(7); manager.scenes = [scene]
        let members = [a, b, u].enumerated().map { index, node in
            SceneDeviceMember(identity: node.timedSchedulerIdentity!,
                parameters: .init(isOn: true, lightness: UInt16(1000 + index * 1000), cct: UInt16(3000 + index * 1000)))
        }
        scene.info.configuration = .init(kind: .devices, name: "Direct", deviceMembers: members)
        let handles = try SceneCommandBuilder.recallHandles(scene: scene)
        precondition(handles.count == 3 && handles.allSatisfy { $0.address == nil })
        precondition(Set(handles.compactMap { $0.model }.map(ObjectIdentifier.init)) == Set([a, b, u].compactMap(\.sceneModel).map(ObjectIdentifier.init)), "Recall must target A/B/U Scene models and exclude same-group X")
        for (node, member) in zip([a, b, u], members) {
            node.sceneExecuteDatas = [.init(sceneNumber: 7, lightness: member.parameters.lightness, cct: member.parameters.cct)]
        }
        let list = ScenesControllerProbe([scene]), collection = UICollectionView()
        list.collectionView(collection, didSelectItemAt: IndexPath(index: 0))
        precondition(MeshAPI.sent.count == 3 && MeshAPI.sent.allSatisfy { $0.address == nil }, "control-only user must retain device Recall")
        precondition(collection.cell.animations == 1)
        list.space.sceneOperates = []
        list.collectionView(collection, didSelectItemAt: IndexPath(index: 0))
        precondition(MeshAPI.sent.count == 3, "revoked control permission must prevent Recall")
        SceneCommandBuilder.applyRecallFeedback(scene: scene)
        precondition(a.lightness == 1000 && b.lightness == 2000 && u.lightness == 3000 && x.lightness == 0)
        precondition(a.temperature == 3000 && b.temperature == 4000 && u.temperature == 5000)
        scene.info.configuration!.pendingOperations = [.init(identity: b.timedSchedulerIdentity!, action: .write)]
        b.lightness = 42
        precondition(SceneCommandBuilder.isSelectable(scene: scene), "pending must remain selectable")
        let pendingHandles = try SceneCommandBuilder.recallHandles(scene: scene)
        precondition(pendingHandles.count == 3)
        SceneCommandBuilder.applyRecallFeedback(scene: scene)
        precondition(b.lightness == 42, "pending expected values must not masquerade as actual state")
        a.lightness = 77; u.lightness = 88
        SceneCommandBuilder.applyRecallFeedback(scene: scene, node: a)
        precondition(a.lightness == 1000 && u.lightness == 88, "single-node callback must not update unsent members")
        EmergencyFireControllerSceneEventManager.blocked = [ObjectIdentifier(u)]
        do { _ = try SceneCommandBuilder.recallHandles(scene: scene); fatalError("ungrouped emergency target bypassed") }
        catch SceneCommandBuilder.RecallFailure.emergency {}
        EmergencyFireControllerSceneEventManager.blocked = []
        var draft = try SceneDraft(scene: scene)
        draft.setMetadata(name: "Renamed", imageId: 3)
        precondition(draft.deviceMembers.count == members.count && draft.deviceMembers.allSatisfy { members.contains($0) } && draft.groupParameters.isEmpty)
        let picker = ScheduleScenePickerProbe([scene])
        let display = SceneGroupDisplayState()
        display.currentSnapshot = SceneGroupSyncSnapshot(groups: [], needsSync: [], pendingDevices: [b.timedSchedulerIdentity!])
        picker.sceneDisplays[ObjectIdentifier(scene)] = display
        precondition(picker.schedule == nil && picker.sceneNeedsSync(scene), "new schedule must show Scene's own pending state")
        picker.collectionView(picker.collectionView, didSelectItemAt: IndexPath(index: 0))
        precondition(picker.selectScene === scene, "pending Scene remains selectable for new Timed")
        let switchPicker = SwitchScenePickerProbe([scene])
        switchPicker.tableView(UITableView(), didSelectRowAt: IndexPath(index: 0))
        precondition(switchPicker.sceneData.scene === scene, "pending Scene remains selectable for physical switches")
        switchPicker.editable = false
        switchPicker.tableView(UITableView(), didSelectRowAt: IndexPath(index: 0))
        precondition(switchPicker.sceneData.scene === scene, "read-only switch picker must not change selection")
        display.currentSnapshot = SceneGroupSyncSnapshot(groups: [], needsSync: [])
        precondition(!picker.sceneNeedsSync(scene))
        picker.schedule = Schedule(2, scene: scene)
        picker.syncDisplay.currentSnapshot = .init(scenes: [ObjectIdentifier(scene)])
        precondition(picker.sceneNeedsSync(scene), "editing schedule must combine its own pending tasks")
        scene.info.projectionPending = true
        precondition(!SceneCommandBuilder.isSelectable(scene: scene))
        scene.info.projectionPending = false; scene.info.configuration!.isDeleting = true
        precondition(!SceneCommandBuilder.isSelectable(scene: scene))
        do { _ = try SceneCommandBuilder.recallHandles(scene: scene); fatalError("deleting scene recalled") } catch {}
        try groupFeedback()
        print("PASS Scene integration: direct Recall, per-device feedback, pending, emergency, metadata and lifecycle")
    }
}

func groupFeedback() throws {
    let manager = MeshNetworkManager.instance
    let group = Group(), a = Node(31), b = Node(32)
    manager.groups = [group]; manager.realNodes = [a, b]; a.group = group; b.group = group
    let scene = Scene(70); manager.scenes = [scene]
    let desired = SceneExecuteData(sceneNumber: 70, isOn: false, lightness: 2000, cct: 4000)
    group.info.sceneExecuteDatas = [desired]
    for explicit in [false, true] {
        scene.info.configuration = explicit ? .init(kind: .groups, name: scene.name) : nil
        group.isOn = true; group.lightness = 123; group.cct = 3333
        a.sceneExecuteDatas = [.init(sceneNumber: 70, isOn: true)]
        b.sceneExecuteDatas = []
        SceneCommandBuilder.applyRecallFeedback(scene: scene)
        checkGroup(group.isOn && group.lightness == 123 && group.cct == 3333, "unsynced \(explicit ? "explicit" : "legacy") group showed desired state")
        a.sceneExecuteDatas = [.init(sceneNumber: 70, isOn: false, lightness: 999, cct: 5000)]
        SceneCommandBuilder.applyRecallFeedback(scene: scene)
        checkGroup(group.isOn, "missing member cache showed desired state")
        b.sceneExecuteDatas = [.init(sceneNumber: 70, isOn: false, lightness: 111, cct: 3000)]
        SceneCommandBuilder.applyRecallFeedback(scene: scene)
        checkGroup(!group.isOn && group.lightness == desired.lightness, "confirmed OFF ignores unsent brightness/CCT fields")
    }
    desired.isOn = true; desired.cct = 6500
    a.effectiveCctRange = 2700...4000; b.effectiveSupportCct = false
    a.sceneExecuteDatas = [desired.deviceTarget(for: a)]; b.sceneExecuteDatas = [desired.deviceTarget(for: b)]
    b.sceneExecuteDatas[0].cct = 0
    group.isOn = false
    SceneCommandBuilder.applyRecallFeedback(scene: scene)
    checkGroup(group.isOn, "confirmed per-device trim/non-CCT values should allow summary")
    a.sceneExecuteDatas[0].cct = 3500; group.isOn = false
    SceneCommandBuilder.applyRecallFeedback(scene: scene)
    checkGroup(!group.isOn, "different cached CCT showed desired summary")
    a.sceneExecuteDatas[0] = desired.deviceTarget(for: a)
    scene.info.configuration!.pendingOperations = [.init(identity: a.timedSchedulerIdentity!, action: .write)]
    SceneCommandBuilder.applyRecallFeedback(scene: scene)
    checkGroup(!group.isOn, "matching cache with explicit pending is not confirmation")
    scene.info.configuration!.pendingOperations = []
    b.lightness = 42; group.lightness = 43
    SceneCommandBuilder.applyRecallFeedback(scene: scene, node: a)
    checkGroup(b.lightness == 42 && group.lightness == 43, "single-node callback wrote other member or group summary")
    a.group = nil; b.group = nil
    SceneCommandBuilder.applyRecallFeedback(scene: scene)
    checkGroup(group.isOn && group.lightness == desired.lightness, "legal empty group must retain original feedback")
    print("PASS group feedback: legacy, cache missing/different, OFF, CCT trim, pending, empty and callback isolation")
}
func checkGroup(_ condition: Bool, _ message: String) {
    if !condition { print("FAIL group feedback: \(message)"); exit(1) }
}

func identifyProductionIdentity() {
    let manager = MeshNetworkManager.instance, node = Node(5)
    node.fingerprint = String(repeating: "ab", count: 32)
    manager.realNodes = [node]
    let controller = IdentifyControllerProbe(.init(meshUUID: manager.meshNetwork!.uuid.uuidString, networkID: "0001"))
    let captured = node.sceneConfigurationIdentity!
    precondition(controller.devicesView.node(for: captured) === node)
    controller.identify(node)
    precondition(LightGroupControlCommandSender.identified == [5], "lowercase production identity must allow Identify")
    node.fingerprint = node.fingerprint.uppercased()
    precondition(controller.devicesView.node(for: captured) === node)
    node.fingerprint = String(repeating: "cd", count: 32)
    precondition(controller.devicesView.node(for: captured) == nil, "different device key cannot match captured selection")
    node.hasIdentity = false; controller.identify(node)
    precondition(LightGroupControlCommandSender.identified == [5], "missing identity cannot Identify")
    node.hasIdentity = true; SceneConfigurationStore.authorized = false; controller.identify(node)
    precondition(LightGroupControlCommandSender.identified == [5], "permission rejection must remain effective")
    SceneConfigurationStore.authorized = true
    manager.realNodes = []
    print("PASS Identify: production selection lookup and Settings action accept lowercase, preserve identity and authority checks")
}
