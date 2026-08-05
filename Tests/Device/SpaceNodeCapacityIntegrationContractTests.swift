import Foundation

@main
struct SpaceNodeCapacityIntegrationContractTests {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected repository root path")
        }
        let root = CommandLine.arguments[1]
        let spaceData = try source(root, "SunSmart/Common/Data/SpaceData.swift")
        let provisioningState = try source(
            root,
            "SunSmart/Main/Device/Model/ProvisioningDevice+Add.swift"
        )
        let lights = try source(
            root,
            "SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift"
        )
        let switches = try source(
            root,
            "SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift"
        )
        let sensors = try source(
            root,
            "SunSmart/Main/Device/Sensors/Controller/DeviceSensorsViewController.swift"
        )
        let others = try source(
            root,
            "SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift"
        )
        let english = try source(root, "SunSmart/en.lproj/Localizable.strings")
        let simplifiedChinese = try source(
            root,
            "SunSmart/zh-Hans.lproj/Localizable.strings"
        )
        let devices = try source(
            root,
            "SunSmart/Main/Device/Controller/DevicesViewController.swift"
        )
        let classic = try source(
            root,
            "SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift"
        )
        let candidateView = try source(
            root,
            "SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift"
        )
        let professional = try source(
            root,
            "SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift"
        )
        let restore = try source(
            root,
            "SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift"
        )
        let lightsUpdateUI = section(
            in: lights,
            from: "private func updateUI(reloadTableView: Bool = true)",
            to: "private func updateAllOnOffItemUI()"
        )

        require(
            spaceData.contains("SpaceNodeCapacityPolicy.maxNodeCount"),
            "SpaceData must expose the shared 500-node policy"
        )
        require(
            !spaceData.contains("var maxDevicesCount: Int = 300"),
            "SpaceData must not retain the 300-node root value"
        )
        require(
            provisioningState.contains("var reservesNodeCapacity: Bool"),
            "Provisioning add state must define the in-flight capacity truth"
        )
        require(
            provisioningState.contains("case .wait, .addConnecting, .adding:"),
            "Only wait, connecting, and adding states reserve node capacity"
        )
        let capacityReservation = section(
            in: provisioningState,
            from: "var reservesNodeCapacity: Bool",
            to: "var blocksVirtualTargetSingleAdd: Bool"
        )
        require(
            !capacityReservation.contains(".success")
                && !capacityReservation.contains(".failed")
                && !capacityReservation.contains(".syncFailed"),
            "Finished states must not reserve an additional Node slot"
        )
        require(
            lightsUpdateUI.contains(
                "let nodeCount = MeshNetworkManager.instance.realNodes.count"
            ) && lightsUpdateUI.contains(
                "footerView.countBtn.setTitle(\"\\(nodeCount)/\\(space.maxDevicesCount)\""
            ),
            "Lights footer must display total Space nodes"
        )
        require(
            switches.contains("\\(MeshNetworkManager.instance.switchs.count)/16"),
            "Switches footer must retain the aggregate 16-switch limit"
        )
        require(
            sensors.contains(
                "\\(MeshNetworkManager.instance.realNodes.count)/\\(space.maxDevicesCount)"
            ),
            "Sensors footer must display total Space nodes"
        )
        require(
            others.contains(
                "\\(MeshNetworkManager.instance.realNodes.count)/\\(space.maxDevicesCount)"
            ),
            "Others footer must display total Space nodes"
        )
        require(
            localizedLimitMessage(in: english)
                && localizedLimitMessage(in: simplifiedChinese),
            "The existing Node limit message must retain a numeric placeholder in both languages"
        )
        let switchAdd = section(
            in: devices,
            from: "private func switchAdd()",
            to: "private func preCreatedDongle()"
        )
        require(
            switchAdd.contains("MeshNetworkManager.instance.switchs.count < 16"),
            "Kinetic Switch add must retain the 16-switch limit"
        )
        require(
            !switchAdd.contains("maxDevicesCount") && !switchAdd.contains("realNodes.count"),
            "Kinetic Switch add must remain independent from the Mesh Node limit"
        )
        let classicCapacityCheck = section(
            in: classic,
            from: "private func checkDeviceAddressesAreSufficient(devices:",
            to: "private func applyDeviceAddressesRequest("
        )
        let classicInFlightCount = section(
            in: classic,
            from: "private var inFlightNodeCount: Int",
            to: "private func showNodeCapacityLimitTip()"
        )
        require(
            classicInFlightCount.contains("scanDevices.filter"),
            "Classic in-flight capacity must include devices hidden by UI filters"
        )
        require(
            classic.contains("private func nodeCapacityAcceptedDevices(")
                && classic.contains("SpaceNodeCapacityPolicy.acceptedPrefix"),
            "Classic Add must define a shared-policy batch gate"
        )
        require(
            classicCapacityCheck.contains(
                "let acceptedDevices = nodeCapacityAcceptedDevices(from: devices)"
            ),
            "Classic Add must apply the batch gate before provisioning"
        )
        require(
            classicCapacityCheck.contains(
                "validateBatteryPowerSwitchLimit(for: acceptedDevices)"
            ),
            "Classic Add must validate Switch capacity after Node batch clipping"
        )
        require(
            classicCapacityCheck.contains(
                "estimatedAddressCount = acceptedDevices.reduce"
            ),
            "Classic address demand must only include accepted Node slots"
        )
        let professionalCapacityCheck = section(
            in: professional,
            from: "private func checkDeviceAddressesAreSufficient(devices:",
            to: "private func applyDeviceAddressesRequest("
        )
        let candidateInFlightCount = section(
            in: candidateView,
            from: "private var inFlightNodeCount: Int",
            to: "private func showNodeCapacityLimitTip()"
        )
        let candidateSelectAll = section(
            in: candidateView,
            from: "private func selectAllBtnClick(sender:",
            to: "private func addSelectedBtnClick()"
        )
        let candidateAddSelected = section(
            in: candidateView,
            from: "private func addSelectedBtnClick()",
            to: "private func closeBtnClick()"
        )
        let candidateRowSelection = section(
            in: candidateView,
            from: "func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)",
            to: "func scrollViewDidScroll(_ scrollView: UIScrollView)"
        )
        require(
            candidateView.contains("SpaceNodeCapacityPolicy.acceptedPrefix"),
            "Professional Candidate selection must clip to remaining Node slots"
        )
        require(
            candidateSelectAll.contains("let canAddDevices = showDevices.filter")
                && !candidateSelectAll.contains("let canAddDevices = candidateDevices.filter"),
            "Professional Select All must allocate slots only to the current category"
        )
        require(
            candidateRowSelection.contains("let selectedNodeCount = showDevices.filter")
                && !candidateRowSelection.contains("let selectedNodeCount = candidateDevices.filter"),
            "Professional row selection must count only the current category selection"
        )
        require(
            candidateInFlightCount.contains("candidateDevices.filter"),
            "Professional hidden in-flight devices must still reserve global capacity"
        )
        require(
            candidateAddSelected.contains("let selectDevices = showDevices.filter"),
            "Professional batch submission must remain scoped to the current category"
        )
        require(
            professional.contains("private func nodeCapacityAcceptedDevices(")
                && professional.contains("SpaceNodeCapacityPolicy.acceptedPrefix"),
            "Professional Controller must define a shared-policy batch gate"
        )
        require(
            professionalCapacityCheck.contains(
                "let acceptedDevices = nodeCapacityAcceptedDevices(from: devices)"
            ),
            "Professional Controller must enforce Node capacity before provisioning"
        )
        require(
            professionalCapacityCheck.contains(
                "validateBatteryPowerSwitchLimit(for: acceptedDevices)"
            ),
            "Professional Power Switch validation must run on the accepted Node batch"
        )
        require(
            professionalCapacityCheck.contains(
                "estimatedAddressCount = acceptedDevices.reduce"
            ),
            "Professional address demand must only include accepted Node slots"
        )
        let restoreAddSelected = section(
            in: restore,
            from: "private func addSelectedBtnClick()",
            to: "private func closeBtnClick()"
        )
        let restoreInFlightCount = section(
            in: restore,
            from: "private var inFlightNodeCount: Int",
            to: "private func showNodeCapacityLimitTip()"
        )
        let restoreAdditionalNodeCost = section(
            in: restore,
            from: "private func additionalNodeCost(",
            to: "private var inFlightNodeCount: Int"
        )
        require(
            restoreAdditionalNodeCost.contains("unprovisionedDevice?.uuid")
                && restoreAdditionalNodeCost.contains("existingNodeUUIDs.contains")
                && restoreAdditionalNodeCost.contains("return 0")
                && restoreAdditionalNodeCost.contains("return 1"),
            "Restore capacity cost must be zero only for a UUID already in realNodes"
        )
        require(
            restoreInFlightCount.contains("sections.flatMap")
                && restoreInFlightCount.contains("addState.reservesNodeCapacity")
                && restoreInFlightCount.contains("additionalNodeCost"),
            "Restore in-flight capacity must count only net-new hidden restore devices"
        )
        let restoreCapacityCheck = section(
            in: restore,
            from: "private func checkDeviceAddressesAreSufficient(devices:",
            to: "private func applyDeviceAddressesRequest("
        )
        let restoreCapacityGate = section(
            in: restore,
            from: "private func nodeCapacityAcceptedRestoreData(",
            to: "private func recordBatteryPowerSwitchTargetSubscriptionSuccessIfNeeded("
        )
        let restoreSelectAll = section(
            in: restore,
            from: "private func selectAllBtnClick(sender:",
            to: "private func addSelectedBtnClick()"
        )
        let restoreRowSelection = section(
            in: restore,
            from: "func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)",
            to: "extension DeviceRestoreViewController: DeviceAddViewCellDelegate"
        )
        require(
            restore.contains("private func nodeCapacityAcceptedRestoreData(")
                && restore.contains("guard space != nil else")
                && restoreCapacityGate.contains("SpaceNodeCapacityPolicy.acceptedElements")
                && !restoreCapacityGate.contains("SpaceNodeCapacityPolicy.acceptedPrefix"),
            "Site-level restore must bypass the shared Space Node batch gate"
        )
        require(
            restoreCapacityGate.contains("let realNodes = MeshNetworkManager.instance.realNodes")
                && restoreCapacityGate.contains("Set(realNodes.map(\\.uuid))")
                && restoreCapacityGate.contains("existingNodeCount: realNodes.count")
                && restoreCapacityGate.contains("nodeCost: { additionalNodeCost"),
            "Restore batch gate must classify every item against current real Node UUIDs"
        )
        require(
            restoreSelectAll.contains("showRestoreData.filter")
                && restoreSelectAll.contains("nodeCapacityAcceptedRestoreData"),
            "Restore Select All must use the shared restore-data capacity gate"
        )
        require(
            restoreRowSelection.contains("showRestoreData.filter")
                && restoreRowSelection.contains("nodeCapacityAcceptedRestoreData")
                && !restoreRowSelection.contains("SpaceNodeCapacityPolicy.acceptedNodeCount"),
            "Restore row selection must use the same restore-data capacity gate"
        )
        require(
            restoreAddSelected.contains(
                "recordPendingBatteryPowerSwitchRestoreLinkGroups(for: acceptedRestoreDatas)"
            ),
            "Restore side effects must only be recorded for accepted Node slots"
        )
        require(
            restoreCapacityCheck.contains(
                "let acceptedRestoreDatas = nodeCapacityAcceptedRestoreData(from: devices)"
            ),
            "Restore must enforce Node capacity before provisioning"
        )
        require(
            restoreCapacityCheck.contains(
                "estimatedAddressCount = acceptedRestoreDatas.reduce"
            ),
            "Restore address demand must only include accepted Node slots"
        )

        print("SpaceNodeCapacityIntegrationContractTests passed")
    }

    private static func source(_ root: String, _ path: String) throws -> String {
        try String(contentsOfFile: root + "/" + path, encoding: .utf8)
    }

    private static func section(in source: String, from start: String, to end: String) -> String {
        guard
            let startRange = source.range(of: start),
            let endRange = source.range(
                of: end,
                range: startRange.upperBound..<source.endIndex
            )
        else {
            return ""
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    private static func localizedLimitMessage(in source: String) -> Bool {
        source.split(separator: "\n").contains { line in
            line.contains("\"devices_number_exceeds_message\"") && line.contains("%d")
        }
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        precondition(condition(), message)
    }
}
