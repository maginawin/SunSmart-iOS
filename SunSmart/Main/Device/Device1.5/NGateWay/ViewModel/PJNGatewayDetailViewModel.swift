//
//  PJNGatewayDetailViewModel.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import Foundation
import NordicSigMeshSDK

struct PJNGatewayDetailViewModel {

    struct SpaceItem {
        let name: String
        let nodesText: String
        let canDelete: Bool
    }

    let title: String
    let meshTitle: String
    let meshStatusText: String
    let meshStatusColorHex: UInt32
    let meshState: PJNGatewayModel.MeshDisplayState
    let meshAssetName: String
    let nodeText: String
    let wifiTitle: String
    let wifiStatusText: String
    let wifiStatusColorHex: UInt32
    let wifiSignalQuality: PJNGatewayModel.WiFiSignalQuality
    let wifiAssetName: String
    let name: String
    let canEditName: Bool
    let activate: Bool
    let canEditActivate: Bool
    let ssidText: String
    let passwordText: String
    let supportsHintText: String
    let isSSIDRefreshing: Bool
    let isAdvancedExpanded: Bool
    let ipMode: PJNGatewayModel.NetworkIPMode
    let canEditNetworkFields: Bool
    let ipAddressText: String
    let subnetMaskText: String
    let gatewayAddressText: String
    let primaryDNSText: String
    let secondaryDNSText: String
    let connectButtonTitle: String
    let isConnectButtonLoading: Bool
    let associatedSpaces: [SpaceItem]
    let canAddAssociatedSpace: Bool
    let showServerWarning: Bool
    let serverWarningText: String
    let canAuthorize: Bool
    let serverAddressText: String
    let portText: String
    let clientIdText: String

    init(site: SiteData, model: PJNGatewayModel, node: Node) {
        title = model.name
        meshTitle = "SIG Mesh"
        meshState = model.meshDisplayState
        meshStatusText = meshState.text
        meshStatusColorHex = meshState.colorHex
        meshAssetName = meshState.assetName
        nodeText = "(\(node.primaryUnicastAddress))\nNode"
        wifiTitle = "WiFi"
        wifiSignalQuality = model.wifiConnectionState == .connected ? model.wifiSignalQuality : .unknown
        wifiStatusText = wifiSignalQuality.text
        wifiStatusColorHex = wifiSignalQuality.colorHex
        wifiAssetName = wifiSignalQuality.assetName
        name = model.name
        canEditName = site.deviceOperates.contains(.edit)
        activate = model.activate
        canEditActivate = site.deviceOperates.contains(.edit)
        ssidText = model.wifiSSID ?? ""
        passwordText = model.wifiPassword ?? ""
        supportsHintText = "ngateway_only_supports_2_4ghz_networks".localizedString
        isSSIDRefreshing = model.isSSIDRefreshing
        isAdvancedExpanded = model.isAdvancedSettingsExpanded
        ipMode = model.networkIPMode
        canEditNetworkFields = model.networkIPMode == .staticIP
        ipAddressText = model.ipAddressText ?? "ngateway_na".localizedString
        subnetMaskText = model.subnetMaskText ?? "ngateway_na".localizedString
        gatewayAddressText = model.gatewayAddressText ?? "ngateway_na".localizedString
        primaryDNSText = model.primaryDNSText ?? "ngateway_na".localizedString
        secondaryDNSText = model.secondaryDNSText ?? "ngateway_na".localizedString
        connectButtonTitle = model.wifiConnectionState == .connected ? "ngateway_disconnect".localizedString : "ngateway_connect_to_wifi".localizedString
        isConnectButtonLoading = model.wifiConnectionState == .connecting
        associatedSpaces = model.associatedSpaces.map {
            SpaceItem(
                name: $0.spaceName,
                nodesText: String(format: "ngateway_nodes_count_format".localizedString, $0.deviceCount),
                canDelete: $0.permission == .editor && site.deviceOperates.contains(.edit)
            )
        }
        canAddAssociatedSpace = site.deviceOperates.contains(.edit)
        showServerWarning = model.mqttServerInfo == nil
        serverWarningText = "ngateway_server_authentication_message".localizedString
        canAuthorize = site.deviceOperates.contains(.edit)

        if let serverInfo = model.mqttServerInfo {
            let server = serverInfo.serverAddress.replacingOccurrences(of: "tcp://", with: "")
            let parts = server.components(separatedBy: ":")
            serverAddressText = parts.first ?? "ngateway_na".localizedString
            portText = parts.count > 1 ? parts[1] : "ngateway_na".localizedString
            clientIdText = serverInfo.clientId
        } else {
            serverAddressText = "ngateway_na".localizedString
            portText = "ngateway_na".localizedString
            clientIdText = "ngateway_na".localizedString
        }
    }
}
