import Foundation

@main
enum SyncTaskBuilderTests {
    static func require(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
    }

    static func validateParents(_ device: SyncDevicesModel) {
        for step in device.steps {
            require(step.parentDeviceModel === device, "step must retain its actual parent")
            for task in step.tasks {
                require(task.parentStepModel === step, "task must retain its actual parent")
                require(task.state == .none, "building must not start tasks")
            }
        }
    }

    static func main() {
        testEmptyAndContext()
        testInitializationAndProfile()
        testScheduleAndExit()
        testSwitchAndOtherOperations()
        testGatewayRecovery()
        testSectionOrdering()
        testDongleDeletion()
        #if !BASELINE_BUILD
        testIndependentScenarioBuilders()
        testInjectedDependenciesAndFailures()
        #endif
        print("PASS: production builders, parent identity, Profile/TimeSet dependencies, Group exit, switches, Gateway recovery and section ordering")
    }

    #if !BASELINE_BUILD
    static func testIndependentScenarioBuilders() {
        let node = Node()
        let profiles: [ProfileType] = [.profileToggleTriggerConditionLuxLock,
            .profileDayToggleTriggerConditionLux, .lightControlSwitch, .occupancyLevel,
            .lightControlStore, .lightControlSwitch]
        let profileSection = SyncDevicesSectionModel(title: "profile")
        SyncProfileTaskBuilder().appendProfile(to: profileSection, datas: [(node, profiles)])
        let device = profileSection.devices[0], steps = device.steps
        validateParents(device)
        require(steps.count == 6, "standalone Profile preserves operation ordering")
        require(steps[2].relevanceStepModels == [steps[0], steps[1]], "switch depends on lock and threshold steps")
        require(steps[3].relevanceStepModels == [steps[0], steps[2]], "content depends on lock and switch steps")
        require(steps[4].relevanceStepModels == [steps[3]], "Store depends on preceding content")
        require(steps[5].relevanceStepModels == [steps[0], steps[1], steps[4]], "next switch waits for previous Store")
        require(steps.flatMap { $0.tasks }.allSatisfy { $0.relevanceTaskModels.isEmpty }, "standalone Profile must preserve step dependencies")

        let proximity = SyncProximityTaskBuilder()
        let section = SyncDevicesSectionModel(title: "proximity")
        proximity.appendProximityLightingItems(to: section, datas: [
            (node, .proximityLightingNeighbor(relayNumber: 2, neighborAddresses: [5, 7])),
            (node, .proximityLightingRelayNumber(3)),
            (node, .proximityLightingEnabled(false)),
            (node, .pirEnabled(true))], title: "path_sequence")
        require(section.devices.count == 3, "only precomputed proximity operations become tasks")
        require(section.devices.map { $0.steps[0].type } == ["path_sequence", "path_sequence", "proximity_lighting_disable"], "proximity labels follow operation intent")
        require(proximity.proximityLightingTaskModels == section.devices.flatMap { $0.steps.flatMap { $0.tasks } }, "completion retains the same task identities")
        section.devices.forEach(validateParents)
        guard case .proximityLightingNeighbor(let relay, let addresses) = proximity.proximityLightingTaskModels[0].operationType.action else { preconditionFailure("neighbor task") }
        require(relay == 2 && addresses == [5, 7], "builder must preserve planner output without recalculating")

        let parameters = SyncDevicesSectionModel(title: "parameters")
        let inputs: [DeviceParameterType] = [.pwmFrequency(frequency: 1), .ratedPower(datas: 2),
            .motionSensitivityRange(range: 3), .defaultTransitionTime(transitionTime: 4),
            .powerCalibration(calibrationValue: 5), .absoluteCctRange(range: 6), .photosensorException(true)]
        SyncParameterTaskBuilder().appendParameters(to: parameters, datas: [(node, []), (node, inputs)])
        require(parameters.devices.count == 1 && parameters.devices[0].steps.count == 7, "parameters omit empty nodes and preserve all seven inputs")
        require(parameters.devices[0].steps.map { $0.type } == ["pwm_frequency", "rated_power", "relative_sensitivity", "transition_time", "power_calibrate", "absolute_cct_range", "photosensor_exception"], "parameter order and labels")
        validateParents(parameters.devices[0])
    }
    #endif

    static func testEmptyAndContext() {
        let node = Node(), group = Group()
        let empty = buildDevice(group: nil, node: node)
        require(empty.configturationDevice == nil && empty.removeDevice == nil, "empty input is not a build failure")
        guard case .all = node.requests[0].0 else { preconditionFailure("devices must use all scope") }
        node.inputs = [.pirEnabled(true)]
        let protected = buildDevice(group: group, node: node, effectiveMemberCount: 3, profileSyncContext: .init(marker: 7), protectsProfileSensors: true)
        require(protected.configturationDevice == nil, "protected Profile must omit duplicate PIR")
        guard case .group(let requestedGroup, let count) = node.requests[1].0 else { preconditionFailure("missing Group scope") }
        require(requestedGroup === group && count == 3 && node.requests[1].1?.marker == 7, "forward context without rebuilding requirements")
        require(buildDevice(group: group, node: node).configturationDevice?.steps.count == 1, "normal PIR must remain")
    }

    static func testDongleDeletion() {
        let node = Node()
        let data = DeviceDongleData(bindNode: node)
        node.inputs = [.deleteCollectionSchedules(scheduleIds: [3, 7])]
        let deleted = buildDongle(data)
        require(deleted.removeDevice?.steps.first?.tasks.count == 2, "Dongle delete-only input must produce both removal tasks")
        require(deleted.configturationDevice == nil, "delete-only must not configure schedules")
        for (task, index) in zip(deleted.removeDevice!.steps[0].tasks, [3, 7]) {
            guard case .collectionSchedule(let actual, let entry) = task.operationType.action else { preconditionFailure("collection operation") }
            require(actual == index && !entry.isValid, "deletion writes invalid entry to the requested index")
        }
        validateParents(deleted.removeDevice!)
        node.inputs = [.syncCollectionSchedules(schedules: [(1, .init(marker: 99))]), .deleteCollectionSchedules(scheduleIds: [2])]
        let mixed = buildDongle(data)
        require(mixed.configturationDevice?.steps.first?.tasks.count == 1 && mixed.removeDevice?.steps.first?.tasks.count == 1, "mixed Dongle changes must preserve both collections")
        guard case .collectionSchedule(let index, let entry) = mixed.configturationDevice!.steps[0].tasks[0].operationType.action else { preconditionFailure("collection configuration") }
        require(index == 1 && entry.marker == 99, "configuration must retain the original entry")
        validateParents(mixed.configturationDevice!); validateParents(mixed.removeDevice!)
        node.inputs = []
        require(buildDongle(data).removeDevice == nil && buildDongle(data).configturationDevice == nil, "empty Dongle plan")
        require(buildDongle(.init(bindNode: nil)).removeDevice == nil, "unbound Dongle has no tasks")
    }

    static func testInitializationAndProfile() {
        let node = Node(), group = Group()
        let profiles: [ProfileType] = [.profileToggleTriggerConditionLuxLock, .profileDayToggleTriggerConditionLux, .lightControlSwitch, .occupancyLevel, .lightControlStore, .daylightSensorConditionRecall]
        node.inputs = [.profile(types: profiles), .subscribeGroup(group: group), .deviceInitialize]
        let device = buildDevice(group: group, node: node).configturationDevice!
        require(device.steps.map(\.type) == ["initialize", "add_to_group", "profile"], "initialization/add/Profile ordering")
        let steps = device.steps, tasks = steps[2].tasks
        require(steps[2].relevanceStepModels.count == 2 && steps[2].relevanceStepModels[0] === steps[0] && steps[2].relevanceStepModels[1] === steps[1], "retain initializer and Group prerequisites")
        require(tasks[2].relevanceTaskModels.elementsEqual([tasks[0], tasks[1]], by: { $0 === $1 }), "Profile switch must wait for lock and threshold")
        require(tasks[3].relevanceTaskModels.elementsEqual([tasks[0], tasks[2]], by: { $0 === $1 }), "Profile content prerequisites")
        require(tasks[4].relevanceTaskModels.elementsEqual([tasks[3]], by: { $0 === $1 }), "Store must wait for current Profile content")
        require(tasks[5].relevanceTaskModels.elementsEqual([tasks[0], tasks[1], tasks[4]], by: { $0 === $1 }), "next Profile must wait for previous Store")
        validateParents(device)
    }

    static func testScheduleAndExit() {
        let node = Node(), group = Group()
        node.inputs = [.syncSchedules(schedules: [.init(name: "enabled", enabled: true), .init(name: "disabled", enabled: false)])]
        let configured = buildDevice(group: nil, node: node).configturationDevice!
        let tasks = configured.steps[0].tasks
        require(tasks.map(\.name) == ["sync_time", "disabled", "enabled"], "one TimeSet; disabled schedules before dependent enabled ones")
        require(tasks[1].relevanceTaskModels.isEmpty && tasks[2].relevanceTaskModels.first === tasks[0], "only enabled Schedule depends on TimeSet")
        validateParents(configured)
        node.timeModel = nil
        require(buildDevice(group: nil, node: node).configturationDevice!.steps[0].tasks.count == 2, "no Time Model means no dedicated time task")
        node.timeModel = 1
        node.groupState = .exitFailure
        node.inputs += [.unsubscribeGroup(group: group), .profile(types: [.occupancyLevel])]
        let result = buildDevice(group: group, node: node)
        require(result.configturationDevice == nil, "exit Schedule belongs to removal")
        let removal = result.removeDevice!, steps = removal.steps
        require(steps.map(\.type) == ["schedule", "profile", "remove_from_group"], "descending exit order")
        require(steps[2].relevanceStepModels.elementsEqual([steps[1]], by: { $0 === $1 }), "Schedule cleanup must not block Group exit")
        validateParents(removal)
        node.groupState = .exitFailure
        node.inputs = [.pirEnabled(false), .proximityLightingEnabled(false), .proximityLightingNeighbor(relayNumber: 2, neighborAddresses: [3])]
        require(buildDevice(group: nil, node: node).removeDevice?.steps.count == 3, "exitFailure routes PIR/topology to removal")
    }

    static func testSwitchAndOtherOperations() {
        let node = Node(), group = Group()
        node.group = group
        let battery = DeviceSwitchData(name: "battery", batteryPowerSwitchData: .init(name: "battery"))
        let kinetic = DeviceSwitchData(name: "kinetic")
        node.inputs = [.syncSwitchs(switchDatas: [battery, kinetic]), .deleteSwitchs(switchDatas: [battery]), .syncSwitchProxy(switchData: kinetic), .deleteSwitchProxy(switchData: kinetic)]
        let result = buildDevice(group: nil, node: node)
        guard case .batteryPowerSwitchTargetSubscription(_, let target, let unsubscribe) = result.configturationDevice!.steps[0].tasks[0].operationType.action else { preconditionFailure("battery target operation") }
        require(target === group && !unsubscribe, "fallback to owning Group")
        require(result.removeDevice!.steps[0].tasks[0].operationType.isDelete, "battery removal remains deletion")
        validateParents(result.configturationDevice!); validateParents(result.removeDevice!)
        node.inputs = [
            .syncScenes(datas: [(.init(name: "scene", number: 1), .init())]),
            .deleteScenes(scenes: [.init(name: "old", number: 2)]),
            .deviceParameterTypes(types: [.pwmFrequency(frequency: 1), .ratedPower(datas: 2), .motionSensitivityRange(range: 3), .defaultTransitionTime(transitionTime: 4), .powerCalibration(calibrationValue: 5), .absoluteCctRange(range: 6), .photosensorException(true)]),
            .emergencyFireControllerAssociations(data: .init(), tasks: [.init(kind: .associationCleanup, title: "remove"), .init(kind: .associationSubscription, title: "add")]),
            .gatewayAssociatedSpaces(datas: [(.init(index: 1), .init(index: 1, boundNetworkKeyIndex: 1))], activate: true),
            .gatewayUnbindAssociatedSpaces(datas: [(.init(index: 2), .init(index: 2, boundNetworkKeyIndex: 2))], activate: false)
        ]
        SpaceData.names = ["1": "Office"]
        let mixed = buildDevice(group: nil, node: node)
        require(mixed.configturationDevice!.steps.map(\.type) == ["scene", "device_parameters", "associationSubscription", "associated_spaces"], "mixed configuration preserves order")
        require(mixed.removeDevice!.steps.map(\.type) == ["remove_scene", "associationCleanup", "unbind_associated_spaces"], "mixed deletion preserves order")
        require(mixed.configturationDevice!.steps[1].tasks.count == 7, "all parameter variants")
        require(mixed.configturationDevice!.steps.last!.tasks[0].name == "Office" && mixed.removeDevice!.steps.last!.tasks[0].name == "space", "Space title lookup and fallback")
        validateParents(mixed.configturationDevice!); validateParents(mixed.removeDevice!)
    }

    static func testGatewayRecovery() {
        let node = Node(), gateway = GatewayModel(), network = MeshNetwork()
        MeshNetworkManager.instance.meshNetwork = network
        require(buildGateway(node: node, gateway: gateway, trigger: .repair) == nil, "reject non-Gateway")
        node.deviceType = .gateway; node.isWiFiGateway = true
        MeshNetworkManager.instance.meshNetwork = nil
        require(buildGateway(node: node, gateway: gateway, trigger: .repair) == nil, "reject missing network")
        MeshNetworkManager.instance.meshNetwork = network
        gateway.associatedSpaces = [.init(appKeyIndex: 1, spaceName: "Office")]
        require(buildGateway(node: node, gateway: gateway, trigger: .repair) == nil, "missing keys must not yield a partial plan")
        network.networkKeys = [.init(index: 0), .init(index: 1), .init(index: 2)]
        network.applicationKeys = [.init(index: 1, boundNetworkKeyIndex: 2)]
        require(buildGateway(node: node, gateway: gateway, trigger: .repair) == nil, "AppKey must bind the matching NetKey")
        network.applicationKeys = [.init(index: 1, boundNetworkKeyIndex: 1), .init(index: 2, boundNetworkKeyIndex: 2)]
        node.networkKeys = network.networkKeys
        let device = buildGateway(node: node, gateway: gateway, trigger: .repair)!, steps = device.steps
        require(steps.map(\.type) == ["initialize", "associated_spaces", "unbind_associated_spaces", "association_project", "gateway_sync_spaces", "server_authorization", "server_information", "gateway_recovery_verification"], "full WiFi recovery chain")
        require(steps[4].relevanceStepModels.elementsEqual([steps[0], steps[1], steps[2]], by: { $0 === $1 }), "Sync Spaces must wait for both association mutations")
        require(steps[6].relevanceStepModels.elementsEqual([steps[0], steps[5]], by: { $0 === $1 }), "server info waits for initialization and authorization")
        require(steps.last!.relevanceStepModels.elementsEqual(Array(steps.dropLast()), by: { $0 === $1 }), "verification waits for the entire recovery chain")
        guard case .gatewayRepairInitialization = steps[0].tasks[0].operationType.action else { preconditionFailure("Repair trigger") }
        guard case .gatewayServerInformation(let retainedGateway) = steps[6].tasks[0].operationType.action else { preconditionFailure("dynamic server info") }
        gateway.mqttServerInfo = .init(marker: 42)
        require(retainedGateway === gateway && retainedGateway.mqttServerInfo?.marker == 42, "keep live Gateway reference across authorization")
        validateParents(device)
        let resync = buildGateway(node: node, gateway: gateway, trigger: .devicesNotSynced)!
        guard case .gatewayRecoveryInitialization = resync.steps[0].tasks[0].operationType.action else { preconditionFailure("Devices not synced trigger") }
        gateway.activate = false
        let inactive = buildGateway(node: node, gateway: gateway, trigger: .repair)!
        guard case .gatewaySubnetAppkeyIndexs(let indexes) = inactive.steps[4].tasks[0].operationType.action else { preconditionFailure("Sync Spaces") }
        require(indexes.isEmpty, "inactive Gateway syncs empty active subnet list")
        let server = buildServerSteps(node: node, gateway: gateway, dependencies: [], includesVerification: true)
        require(server.map(\.type) == ["server_authorization", "server_information", "gateway_recovery_verification"], "standalone server chain")
        require(server[1].relevanceStepModels.first === server[0] && server[2].relevanceStepModels.first === server[1], "standalone server dependencies")
        node.isWiFiGateway = false
        let legacy = buildGateway(node: node, gateway: gateway, trigger: .repair)!
        require(!legacy.steps.contains { $0.type == "server_authorization" }, "non-WiFi retains existing MQTT path")
    }

    static func testSectionOrdering() {
        let section = SyncDevicesSectionModel(title: "configuration")
        let direct = SyncDevicesModel(name: "direct", address: 1)
        let grouped = SyncDevicesModel(name: "grouped", address: 2)
        let proxy = SyncDevicesModel(name: "proxy", address: 3)
        section.devices = [direct]
        section.groups = [SyncDevicesGroupModel(groupName: "group", groupAddress: 4, deviceModels: [grouped])]
        section.switchProxy = SyncDevicesSwitchProxyModel(name: "proxy", deviceModel: proxy)
        require(section.allModels.compactMap { $0 as? SyncDevicesModel }.map(\.address) == [3, 2, 1], "Proxy precedes Group and direct devices")
        section.prefersDevicesBeforeGroups = true
        require(section.allModels.compactMap { $0 as? SyncDevicesModel }.map(\.address) == [3, 1, 2], "device-first exception retains Proxy order")
        require(section.rowModels.count != section.allModels.count, "execution must not depend on collapsed row visibility")
    }

    #if !BASELINE_BUILD
    static func testInjectedDependenciesAndFailures() {
        let node = Node(), gateway = GatewayModel()
        let absent = SyncGatewayTaskBuilder(meshNetwork: { nil })
        guard case .failure(.notGateway) = absent.makeRecoveryDevice(node: node, gateway: gateway, trigger: .repair) else {
            preconditionFailure("non-Gateway diagnostic")
        }
        node.deviceType = .gateway
        guard case .failure(.missingMeshNetwork) = absent.makeRecoveryDevice(node: node, gateway: gateway, trigger: .repair) else {
            preconditionFailure("missing network diagnostic")
        }
        let network = MeshNetwork()
        var networkReads = 0
        let builder = SyncGatewayTaskBuilder(meshNetwork: { networkReads += 1; return network }, spaceName: { "Injected \($0)" })
        gateway.associatedSpaces = [.init(appKeyIndex: 2, spaceName: "Office")]
        guard case .failure(.missingAssociatedSpaceKeys) = builder.makeRecoveryDevice(node: node, gateway: gateway, trigger: .repair) else {
            preconditionFailure("missing keys diagnostic")
        }
        require(networkReads == 1, "read the supplied network once per build")
        network.networkKeys = [.init(index: 2)]
        network.applicationKeys = [.init(index: 2, boundNetworkKeyIndex: 2), .init(index: 3, boundNetworkKeyIndex: 3)]
        node.networkKeys = [.init(index: 3)]
        let device = try! builder.makeRecoveryDevice(node: node, gateway: gateway, trigger: .repair).get()
        require(networkReads == 2, "read current network on the next build rather than freezing it in init")
        require(device.steps[2].tasks[0].name == "Injected 3", "recovery cleanup uses supplied Space lookup")
        var lookedUp: [String] = []
        node.inputs = [.gatewayAssociatedSpaces(datas: [(.init(index: 2), .init(index: 2, boundNetworkKeyIndex: 2))], activate: true)]
        let ordinary = SyncDeviceTaskBuilder(spaceName: { lookedUp.append($0); return "Selected Space" })
        let result = ordinary.makeDeviceModels(group: nil, node: node)
        require(lookedUp == ["2"] && result.configturationDevice!.steps[0].tasks[0].name == "Selected Space", "ordinary builder uses supplied lookup at build time")
    }
    #endif
}
