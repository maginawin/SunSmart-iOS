//
//  PJNGatewayModel.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import Foundation
import NordicSigMeshSDK

final class PJNGatewayModel: GatewayModel {

    enum MeshDisplayState {
        case online
        case offline

        var assetName: String {
            switch self {
            case .online:
                return "meshOnline"
            case .offline:
                return "meshOffline"
            }
        }

        var text: String {
            switch self {
            case .online:
                return "ngateway_online".localizedString
            case .offline:
                return "ngateway_offline".localizedString
            }
        }

        var colorHex: UInt32 {
            switch self {
            case .online:
                return 0x21B573
            case .offline:
                return 0xC7CBD4
            }
        }
    }

    enum WiFiConnectionState {
        case disconnected
        case connecting
        case connected
    }

    enum WiFiSignalQuality {
        case excellent
        case good
        case poor
        case bad
        case noSignal
        case noInternet
        case unknown

        var text: String {
            switch self {
            case .excellent:
                return "ngateway_excellent".localizedString
            case .good:
                return "ngateway_good".localizedString
            case .poor:
                return "ngateway_poor".localizedString
            case .bad:
                return "ngateway_bad".localizedString
            case .noSignal:
                return "ngateway_no_signal".localizedString
            case .noInternet:
                return "ngateway_no_internet".localizedString
            case .unknown:
                return "ngateway_no_signal".localizedString
            }
        }

        var assetName: String {
            switch self {
            case .excellent:
                return "Excellent"
            case .good:
                return "Good"
            case .poor:
                return "Poor"
            case .bad:
                return "Bad"
            case .noSignal:
                return "No Signal"
            case .noInternet:
                return "No Internet"
            case .unknown:
                return "No Signal"
            }
        }

        var colorHex: UInt32 {
            switch self {
            case .excellent, .good:
                return 0x21B573
            case .poor:
                return 0xF59E0B
            case .bad, .noSignal, .noInternet:
                return 0xC7CBD4
            case .unknown:
                return 0xC7CBD4
            }
        }

        var symbolName: String {
            switch self {
            case .excellent:
                return "wifi"
            case .good:
                return "wifi"
            case .poor:
                return "wifi"
            case .bad:
                return "wifi.exclamationmark"
            case .noSignal:
                return "wifi.slash"
            case .noInternet:
                return "exclamationmark.triangle.fill"
            case .unknown:
                return "wifi.slash"
            }
        }
    }

    enum NetworkIPMode {
        case dhcp
        case staticIP
    }

    var wifiSSID: String?
    var wifiPassword: String?
    var wifiConnectionState: WiFiConnectionState = .disconnected
    var wifiSignalQuality: WiFiSignalQuality = .unknown
    var networkIPMode: NetworkIPMode = .dhcp
    var ipAddressText: String?
    var subnetMaskText: String?
    var gatewayAddressText: String?
    var primaryDNSText: String?
    var secondaryDNSText: String?
    var isAdvancedSettingsExpanded: Bool = true
    var isSSIDRefreshing = false

    init(gatewayModel: GatewayModel) {
        super.init(
            siteId: gatewayModel.siteId,
            name: gatewayModel.name,
            address: gatewayModel.address,
            mac: gatewayModel.mac,
            lastUpdate: gatewayModel.lastUpdate,
            activate: gatewayModel.activate,
            associatedSpaces: gatewayModel.associatedSpaces,
            apn: gatewayModel.apn,
            mqttServerInfo: gatewayModel.mqttServerInfo
        )
        connectStatus = gatewayModel.connectStatus
        lastOnlineTime = gatewayModel.lastOnlineTime
        resetTime = gatewayModel.resetTime
        lastUploadCloudTimestamp = gatewayModel.lastUploadCloudTimestamp
        syncCloudError = gatewayModel.syncCloudError
        maxAssociatedSpaces = gatewayModel.maxAssociatedSpaces
        isSimInserted = gatewayModel.isSimInserted
        csqRssi = gatewayModel.csqRssi
        wifiSignalQuality = Self.resolveWiFiSignalQuality(csqRssi: gatewayModel.csqRssi)
    }

    override func copy() -> Self {
        let copy = PJNGatewayModel(gatewayModel: self)
        copy.wifiSSID = wifiSSID
        copy.wifiPassword = wifiPassword
        copy.wifiConnectionState = wifiConnectionState
        copy.wifiSignalQuality = wifiSignalQuality
        copy.networkIPMode = networkIPMode
        copy.ipAddressText = ipAddressText
        copy.subnetMaskText = subnetMaskText
        copy.gatewayAddressText = gatewayAddressText
        copy.primaryDNSText = primaryDNSText
        copy.secondaryDNSText = secondaryDNSText
        copy.isAdvancedSettingsExpanded = isAdvancedSettingsExpanded
        copy.isSSIDRefreshing = isSSIDRefreshing
        return copy as! Self
    }

    var meshDisplayState: MeshDisplayState {
        node?.state == true ? .online : .offline
    }

    var wifiDisplayText: String {
        wifiSignalQuality.text
    }

    var wifiDisplayColorHex: UInt32 {
        wifiSignalQuality.colorHex
    }

    static func resolveWiFiSignalQuality(csqRssi: Int?) -> WiFiSignalQuality {
        guard let csqRssi else {
            return .unknown
        }

        if csqRssi >= 24 {
            return .excellent
        } else if csqRssi >= 15 {
            return .good
        } else if csqRssi >= 8 {
            return .poor
        } else if csqRssi >= 1 {
            return .bad
        } else {
            return .noSignal
        }
    }
}
