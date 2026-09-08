import Foundation
import NordicSigMeshSDK

/// 网关完整恢复和服务器恢复的任务组装；授权与消息生成仍由执行阶段负责。
struct SyncGatewayTaskBuilder {
    enum BuildFailure: Error {
        case notGateway
        case missingMeshNetwork
        case missingAssociatedSpaceKeys
    }

    private let meshNetwork: () -> MeshNetwork?
    private let spaceName: (String) -> String?

    init(
        meshNetwork: @escaping () -> MeshNetwork? = { MeshNetworkManager.instance.meshNetwork },
        spaceName: @escaping (String) -> String? = { SpaceData.load(subNetworkId: $0)?.name }
    ) {
        self.meshNetwork = meshNetwork
        self.spaceName = spaceName
    }

    func makeServerRecoverySteps(
        node: Node,
        gateway: GatewayModel,
        authorizationDependencies: [SyncDeviceStepModel],
        includesVerification: Bool
    ) -> [SyncDeviceStepModel] {
        let authorizationTask = SyncDeviceStepTaskModel(
            name: "server_authorization".localizedString,
            operationType: .configuration(
                node: node,
                type: .gatewayServerAuthorization(gateway: gateway)
            )
        )
        let authorizationStep = SyncDeviceStepModel(
            type: "server_authorization".localizedString,
            state: .none,
            tasks: [authorizationTask]
        )
        authorizationTask.parentStepModel = authorizationStep
        authorizationStep.relevanceStepModels = authorizationDependencies

        let informationTask = SyncDeviceStepTaskModel(
            name: "server_information".localizedString,
            operationType: .configuration(
                node: node,
                type: .gatewayServerInformation(gateway: gateway)
            )
        )
        let informationStep = SyncDeviceStepModel(
            type: "server_information".localizedString,
            state: .none,
            tasks: [informationTask]
        )
        informationTask.parentStepModel = informationStep
        informationStep.relevanceStepModels = authorizationDependencies + [authorizationStep]

        var steps = [authorizationStep, informationStep]
        if includesVerification {
            let verificationTask = SyncDeviceStepTaskModel(
                name: "gateway_recovery_verification".localizedString,
                operationType: .configuration(
                    node: node,
                    type: .gatewayServerInformationVerification(gateway: gateway)
                )
            )
            let verificationStep = SyncDeviceStepModel(
                type: "gateway_recovery_verification".localizedString,
                state: .none,
                tasks: [verificationTask]
            )
            verificationTask.parentStepModel = verificationStep
            verificationStep.relevanceStepModels = [informationStep]
            steps.append(verificationStep)
        }
        return steps
    }

    func makeRecoveryDevice(
        node: Node,
        gateway: GatewayModel,
        trigger: SyncDevicesViewController.GatewayRecoveryTrigger
    ) -> Result<SyncDevicesModel, BuildFailure> {
        guard node.deviceType == .gateway else {
            return .failure(.notGateway)
        }
        guard let meshNetwork = meshNetwork() else {
            return .failure(.missingMeshNetwork)
        }

        let initializationAction: ActionType
        switch trigger {
        case .devicesNotSynced:
            initializationAction = .gatewayRecoveryInitialization
        case .repair:
            initializationAction = .gatewayRepairInitialization
        }

        let initializeTask = SyncDeviceStepTaskModel(
            name: "initialize".localizedString,
            operationType: .configuration(node: node, type: initializationAction)
        )
        let initializeStep = SyncDeviceStepModel(
            type: "initialize".localizedString,
            state: .none,
            tasks: [initializeTask]
        )
        initializeTask.parentStepModel = initializeStep

        var steps = [initializeStep]
        var associationMutationSteps: [SyncDeviceStepModel] = []
        let associatedSpaceKeys = gateway.associatedSpaces.compactMap { space -> (GatewaySpaceData, NetworkKey, ApplicationKey)? in
            guard let networkKey = meshNetwork.networkKeys.first(where: { $0.index == space.appKeyIndex }),
                  let applicationKey = meshNetwork.applicationKeys.first(where: {
                      $0.index == space.appKeyIndex && $0.boundNetworkKeyIndex == networkKey.index
                  }) else {
                return nil
            }
            return (space, networkKey, applicationKey)
        }
        guard associatedSpaceKeys.count == gateway.associatedSpaces.count else {
            return .failure(.missingAssociatedSpaceKeys)
        }

        if !associatedSpaceKeys.isEmpty {
            let tasks = associatedSpaceKeys.map { space, networkKey, applicationKey in
                SyncDeviceStepTaskModel(
                    name: space.spaceName,
                    operationType: .configuration(
                        node: node,
                        type: .gatewayRecoveryAssociatedSpace(
                            networkKey: networkKey,
                            applicationKey: applicationKey,
                            activate: gateway.activate
                        )
                    )
                )
            }
            let step = SyncDeviceStepModel(
                type: "associated_spaces".localizedString,
                state: .none,
                tasks: tasks
            )
            tasks.forEach { $0.parentStepModel = step }
            step.relevanceStepModels = [initializeStep]
            steps.append(step)
            associationMutationSteps.append(step)
        }

        let desiredAppKeyIndexes = Set(
            gateway.associatedSpaces.map(\.appKeyIndex)
        )
        let obsoleteAssociatedSpaceKeys = node.networkKeys
            .filter { networkKey in
                networkKey.isSecondary
                    && !desiredAppKeyIndexes.contains(networkKey.index)
            }
            .compactMap { networkKey -> (NetworkKey, ApplicationKey)? in
                guard let applicationKey = meshNetwork.applicationKeys.first(where: {
                    $0.index == networkKey.index
                        && $0.boundNetworkKeyIndex == networkKey.index
                }) else {
                    return nil
                }
                return (networkKey, applicationKey)
            }

        if !obsoleteAssociatedSpaceKeys.isEmpty {
            let tasks = obsoleteAssociatedSpaceKeys.map { networkKey, applicationKey in
                let spaceName = spaceName(networkKey.networkId.hex) ?? "space".localizedString
                return SyncDeviceStepTaskModel(
                    name: spaceName,
                    operationType: .delete(
                        node: node,
                        type: .gatewayUnbindAssociatedSpace(
                            networkKey: networkKey,
                            applicationKey: applicationKey,
                            activate: gateway.activate
                        )
                    )
                )
            }
            let step = SyncDeviceStepModel(
                type: "unbind_associated_spaces".localizedString,
                state: .none,
                tasks: tasks
            )
            tasks.forEach { $0.parentStepModel = step }
            step.relevanceStepModels = [initializeStep]
            steps.append(step)
            associationMutationSteps.append(step)
        }

        let projectTask = SyncDeviceStepTaskModel(
            name: "association_project".localizedString,
            operationType: .configuration(
                node: node,
                type: .gatewayAssociationProjectId(projectId: gateway.siteId)
            )
        )
        let projectStep = SyncDeviceStepModel(
            type: "association_project".localizedString,
            state: .none,
            tasks: [projectTask]
        )
        projectTask.parentStepModel = projectStep
        projectStep.relevanceStepModels = [initializeStep]
        steps.append(projectStep)

        let targetAppKeyIndexes: [KeyIndex] = gateway.activate
            ? Array(Set(gateway.associatedSpaces.map(\.appKeyIndex))).sorted()
            : []
        let syncSpacesTask = SyncDeviceStepTaskModel(
            name: "gateway_sync_spaces".localizedString,
            operationType: .configuration(
                node: node,
                type: .gatewaySubnetAppkeyIndexs(appkeyIndexs: targetAppKeyIndexes)
            )
        )
        let syncSpacesStep = SyncDeviceStepModel(
            type: "gateway_sync_spaces".localizedString,
            state: .none,
            tasks: [syncSpacesTask]
        )
        syncSpacesTask.parentStepModel = syncSpacesStep
        syncSpacesStep.relevanceStepModels = [initializeStep] + associationMutationSteps
        steps.append(syncSpacesStep)

        if node.isWiFiGateway {
            steps.append(
                contentsOf: makeServerRecoverySteps(
                    node: node,
                    gateway: gateway,
                    authorizationDependencies: [initializeStep],
                    includesVerification: false
                )
            )
        } else if let mqttServerInfo = gateway.mqttServerInfo {
            let serverTask = SyncDeviceStepTaskModel(
                name: "server_information".localizedString,
                operationType: .configuration(
                    node: node,
                    type: .gatewayMQTTInformation(mqttInformation: mqttServerInfo)
                )
            )
            let serverStep = SyncDeviceStepModel(
                type: "server_information".localizedString,
                state: .none,
                tasks: [serverTask]
            )
            serverTask.parentStepModel = serverStep
            serverStep.relevanceStepModels = [initializeStep]
            steps.append(serverStep)
        }

        let verificationTask = SyncDeviceStepTaskModel(
            name: "gateway_recovery_verification".localizedString,
            operationType: .configuration(
                node: node,
                type: .gatewayRecoveryVerification(gateway: gateway)
            )
        )
        let verificationStep = SyncDeviceStepModel(
            type: "gateway_recovery_verification".localizedString,
            state: .none,
            tasks: [verificationTask]
        )
        verificationTask.parentStepModel = verificationStep
        verificationStep.relevanceStepModels = steps
        steps.append(verificationStep)

        let deviceModel = SyncDevicesModel(name: node.name ?? gateway.name, address: node.primaryUnicastAddress)
        deviceModel.imageName = node.iconName
        deviceModel.steps = steps
        steps.forEach { $0.parentDeviceModel = deviceModel }
        return .success(deviceModel)
    }

}
