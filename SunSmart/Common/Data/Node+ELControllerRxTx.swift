//
//  Node+ELControllerRxTx.swift
//  SunSmart
//
//  Created by SunSmart on 2026/6/26.
//

import Foundation
import NordicSigMeshSDK

enum ELControllerRxTxConnectionState: Int {
    case unknown = 0
    case normal = 1
    case fault = 2
}

private enum ELControllerRxTxAssociatedKeys {
    static var connectionState: UInt8 = 0
}

extension Node {

    var supportsELControllerRxTxConnectionState: Bool {
        companyIdentifier == 0x0A78 && productIdentifier == 0x24C1
    }

    var elControllerRxTxConnectionState: ELControllerRxTxConnectionState {
        get {
            let rawValue = objc_getAssociatedObject(self, &ELControllerRxTxAssociatedKeys.connectionState) as? Int
            return rawValue.flatMap(ELControllerRxTxConnectionState.init(rawValue:)) ?? .unknown
        }
        set {
            objc_setAssociatedObject(
                self,
                &ELControllerRxTxAssociatedKeys.connectionState,
                newValue.rawValue,
                .OBJC_ASSOCIATION_RETAIN
            )
        }
    }

    @discardableResult
    func updateELControllerRxTxConnectionState(_ state: ELControllerRxTxConnectionState) -> Bool {
        guard supportsELControllerRxTxConnectionState else {
            return false
        }
        guard elControllerRxTxConnectionState != state else {
            return false
        }
        elControllerRxTxConnectionState = state
        NotificationCenter.default.post(name: .init(deviceStateUpdateNotificationName), object: self)
        return true
    }

    var elControllerLightsIconName: String {
        guard supportsELControllerRxTxConnectionState else {
            return iconName
        }
        switch elControllerRxTxConnectionState {
        case .unknown, .normal:
            return iconName
        case .fault:
            return unsyncIconName
        }
    }
}
