//
//  PJNGatewayPageViewModel.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import Foundation
import NetworkExtension
import NordicSigMeshSDK
import SwiftyJSON

final class PJNGatewayPageViewModel {
    enum DeleteGatewayError: LocalizedError {
        case noPermission

        var errorDescription: String? {
            switch self {
            case .noPermission:
                return "no_permission".localizedString
            }
        }
    }

    let site: SiteData
    let gateway: Gateway
    let node: Node
    let gatewayModel: PJNGatewayModel

    init(site: SiteData, gateway: Gateway) {
        self.site = site
        self.gateway = gateway
        self.node = gateway.node
        self.gatewayModel = PJNGatewayModel(gatewayModel: gateway.model)
    }

    var title: String {
        gatewayModel.name
    }

    var detailViewModel: PJNGatewayDetailViewModel {
        PJNGatewayDetailViewModel(site: site, model: gatewayModel, node: node)
    }

    func updateName(_ name: String) {
        gatewayModel.name = name
    }

    func updateActivate(_ isOn: Bool) {
        gatewayModel.activate = isOn
    }

    func toggleAdvancedSettings() {
        gatewayModel.isAdvancedSettingsExpanded.toggle()
    }

    func updateIPMode(_ mode: PJNGatewayModel.NetworkIPMode) {
        gatewayModel.networkIPMode = mode
    }

    func updateIPAddress(_ text: String) {
        gatewayModel.ipAddressText = text
    }

    func updateSubnetMask(_ text: String) {
        gatewayModel.subnetMaskText = text
    }

    func updateGatewayAddress(_ text: String) {
        gatewayModel.gatewayAddressText = text
    }

    func updatePrimaryDNS(_ text: String) {
        gatewayModel.primaryDNSText = text
    }

    func updateSecondaryDNS(_ text: String) {
        gatewayModel.secondaryDNSText = text
    }

    func availableAssociatedSpaces() -> [GatewaySpaceData] {
        guard let meshNetwork = MeshNetworkManager.instance.meshNetwork else {
            return []
        }

        return site.spaces
            .filter {
                ($0.permission == .owner || $0.permission == .editor)
                    && $0.state == .normal
                    && !$0.requiresPasswordVerification
                    && ($0.relevanceGatewayId == nil || $0.relevanceGatewayId == gateway.mac)
            }
            .compactMap { space in
                guard let appkey = meshNetwork.applicationKeys.first(where: { $0.boundNetworkKey.networkId.hex == space.meshNetworkId }) else {
                    return nil
                }
                let permission: GatewaySpaceData.GatewaySpacePermission
                if space.canEditing {
                    permission = .editor
                } else if space.state == .waitDeleted {
                    permission = .permissionLoss
                } else if space.requiresPasswordVerification {
                    permission = .permissionException
                } else {
                    permission = .none
                }
                return GatewaySpaceData(
                    spaceId: space.id,
                    spaceName: space.name,
                    deviceCount: space.deviceCount,
                    appKeyIndex: appkey.index,
                    permission: permission
                )
            }
    }

    func applyAssociatedSpaces(_ spaces: [GatewaySpaceData]) {
        gatewayModel.associatedSpaces = spaces
        gateway.model.associatedSpaces = spaces
        gateway.save()
    }

    func associatedSpace(at index: Int) -> GatewaySpaceData? {
        guard gatewayModel.associatedSpaces.indices.contains(index) else {
            return nil
        }
        return gatewayModel.associatedSpaces[index]
    }

    func unbindAssociatedSpace(_ space: GatewaySpaceData, completion: @escaping (Result<Void, NetworkApiError>) -> Void) {
        NetworkRequest.shared.request(.gatewayUnbindSpace(spaceId: space.spaceId, gatewayId: gateway.mac)) { [weak self] result in
            guard let self else {
                return
            }
            switch result {
            case .success:
                self.gatewayModel.associatedSpaces.removeAll(where: { $0.spaceId == space.spaceId })
                self.gateway.model.associatedSpaces.removeAll(where: { $0.spaceId == space.spaceId })
                self.gateway.save()
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func deleteGatewayRegistrationIfNeeded() async throws -> Bool {
        guard gatewayModel.mqttServerInfo != nil || gatewayModel.lastUploadCloudTimestamp != nil else {
            return false
        }

        if site.permission != .owner {
            let bindSpaces = try await loadBoundAssociatedSpaces()
            if bindSpaces.contains(where: { $0.permission == .none || $0.permission == .permissionLoss || $0.permission == .permissionException }) {
                throw DeleteGatewayError.noPermission
            }
        }

        let deleteResult = await NetworkRequest.shared.request(.gatewayDelete(gatewayId: gateway.mac))
        switch deleteResult {
        case .success:
            gatewayModel.mqttServerInfo = nil
            gatewayModel.associatedSpaces.removeAll()
            gatewayModel.lastUploadCloudTimestamp = nil
            gateway.model.mqttServerInfo = nil
            gateway.model.associatedSpaces.removeAll()
            gateway.model.lastUploadCloudTimestamp = nil
            gateway.save()
            return true
        case .failure(let error):
            throw error
        }
    }

    private func loadBoundAssociatedSpaces() async throws -> [GatewaySpaceData] {
        let result = await NetworkRequest.shared.request(.gatewayAssociationSpaceList(siteId: gatewayModel.siteId, gatewayId: gatewayModel.mac))
        switch result {
        case .success(let response):
            let list = JSON(response)["data"]["refSpaces"].arrayValue
            return list.compactMap { spaceJson in
                guard
                    let spaceId = spaceJson["spaceId"].string,
                    let spaceName = spaceJson["spaceName"].string,
                    let deviceCount = spaceJson["deviceCount"].int,
                    let appKeyIndex = spaceJson["appKey"]["index"].uInt16
                else {
                    return nil
                }
                let gatewaySpace = GatewaySpaceData(spaceId: spaceId, spaceName: spaceName, deviceCount: deviceCount, appKeyIndex: appKeyIndex)
                if let space = SpaceData.load(siteId: gatewayModel.siteId, spaceId: spaceId).first {
                    if space.canEditing {
                        gatewaySpace.permission = .editor
                    } else if space.state == .waitDeleted {
                        gatewaySpace.permission = .permissionLoss
                    } else if space.requiresPasswordVerification {
                        gatewaySpace.permission = .permissionException
                    } else {
                        gatewaySpace.permission = .none
                    }
                }
                return gatewaySpace
            }
        case .failure(let error):
            throw error
        }
    }

    func refreshCurrentSSID(completion: @escaping (_ hasConnectedSSID: Bool) -> Void) {
        if #available(iOS 14.0, *) {
            NEHotspotNetwork.fetchCurrent { [weak self] network in
                guard let self else { return }
                let ssid = network?.ssid.trimmingCharacters(in: .whitespacesAndNewlines)
                self.gatewayModel.wifiSSID = (ssid?.isEmpty == false) ? ssid : nil
                completion(self.gatewayModel.wifiSSID != nil)
            }
        } else {
            gatewayModel.wifiSSID = nil
            completion(false)
        }
    }

    func refreshNetworkDetails(completion: @escaping (_ hasConnectedSSID: Bool) -> Void) {
        refreshCurrentSSID { [weak self] hasConnectedSSID in
            guard let self else { return }
            self.gatewayModel.isAdvancedSettingsExpanded = true
            if hasConnectedSSID {
                self.gatewayModel.wifiConnectionState = .connected
                self.gatewayModel.wifiSignalQuality = self.gatewayModel.wifiSignalQuality == .unknown ? .good : self.gatewayModel.wifiSignalQuality
                self.gatewayModel.ipAddressText = self.gatewayModel.ipAddressText ?? "192.162.1.144"
                self.gatewayModel.subnetMaskText = self.gatewayModel.subnetMaskText ?? "255.255.255.0"
                self.gatewayModel.gatewayAddressText = self.gatewayModel.gatewayAddressText ?? "192.162.1.1"
                self.gatewayModel.primaryDNSText = self.gatewayModel.primaryDNSText ?? "8.8.8.8"
                self.gatewayModel.secondaryDNSText = self.gatewayModel.secondaryDNSText ?? "8.8.4.4"
            }
            completion(hasConnectedSSID)
        }
    }

    var requires2_4GHzSwitchPrompt: Bool {
        guard let ssid = gatewayModel.wifiSSID?.lowercased(), !ssid.isEmpty else {
            return true
        }
        return !ssid.contains("2.4")
    }

    var shouldShow2_4GHzSwitchPrompt: Bool {
        guard let ssid = gatewayModel.wifiSSID?.lowercased(), !ssid.isEmpty else {
            return false
        }
        return !ssid.contains("2.4")
    }

    var hasConnectedSSID: Bool {
        guard let ssid = gatewayModel.wifiSSID else { return false }
        return !ssid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func handleConnectAction(completion: @escaping () -> Void) {
        switch gatewayModel.wifiConnectionState {
        case .disconnected:
            gatewayModel.wifiConnectionState = .connecting
            completion()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self else { return }
                self.gatewayModel.wifiConnectionState = .connected
                self.gatewayModel.wifiSSID = self.gatewayModel.wifiSSID?.isEmpty == false ? self.gatewayModel.wifiSSID : "Private Connection"
                self.gatewayModel.wifiPassword = self.gatewayModel.wifiPassword?.isEmpty == false ? self.gatewayModel.wifiPassword : "12345678"
                self.gatewayModel.wifiSignalQuality = .excellent
                self.gatewayModel.ipAddressText = self.gatewayModel.ipAddressText ?? "192.162.1.144"
                self.gatewayModel.subnetMaskText = self.gatewayModel.subnetMaskText ?? "255.255.255.0"
                self.gatewayModel.gatewayAddressText = self.gatewayModel.gatewayAddressText ?? "192.162.1.1"
                self.gatewayModel.primaryDNSText = self.gatewayModel.primaryDNSText ?? "8.8.8.8"
                self.gatewayModel.secondaryDNSText = self.gatewayModel.secondaryDNSText ?? "8.8.4.4"
                completion()
            }
        case .connecting:
            break
        case .connected:
            gatewayModel.wifiConnectionState = .disconnected
            gatewayModel.wifiSSID = nil
            completion()
        }
    }

    func authorizeServerIfNeeded() async throws -> Bool {
        guard gatewayModel.mqttServerInfo == nil else {
            return false
        }
        guard let nodeDict = await node.export() else {
            throw NetworkApiError.unknown
        }

        let result = await NetworkRequest.shared.request(
            .gatewayRegister(
                siteId: site.id,
                gatewayId: gateway.mac,
                nodeId: node.uuid.uuidString,
                node: nodeDict,
                updateTimestamp: gateway.lastUpdate
            )
        )

        switch result {
        case .success(let response):
            guard
                let data = response["data"] as? [String: Any],
                let username = data["mqttUsername"] as? String,
                let password = data["mqttPassword"] as? String,
                let clientId = data["mqttClientId"] as? String,
                let host = data["host"] as? String,
                let port = data["port"] as? Int
            else {
                throw NetworkApiError.unknown
            }

            let mqttServerInfo = GatewayInformation.MQTTConnectInformation(
                customId: customId,
                serverAddress: "tcp://\(host):\(port)",
                userName: username,
                password: password,
                clientId: clientId,
                keepalive: 60,
                clearSession: true,
                authMode: .none,
                sslVersion: .all
            )
            gatewayModel.mqttServerInfo = mqttServerInfo
            gateway.model.mqttServerInfo = mqttServerInfo
            gateway.save()

            if let vendorModel = node.sunricherVendorModel {
                _ = await MeshAPI.sendMessage(
                    message: SunricherVendorSet(function: .gatewayMQTTConnectInfoSet(connectInfo: mqttServerInfo)),
                    model: vendorModel
                )
            }
            return true
        case .failure(let error):
            throw error
        }
    }

    func saveChanges() {
        gateway.model.name = gatewayModel.name
        gateway.model.activate = gatewayModel.activate
        gateway.model.save()
    }
}
