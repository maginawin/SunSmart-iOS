import Foundation

enum WiFiGatewayV19Subcode: UInt8, CaseIterable {
    case credentialsSet = 0x0D
    case connectionStatus = 0x0E
    case rssiStatus = 0x0F
    case dfuStart = 0x10
    case dfuStatus = 0x11
    case credentialsRead = 0x12
    case credentialsClear = 0x13
    case firmwareVersion = 0x14
    case dfuCancel = 0x15
}

enum WiFiGatewayV19Timing {
    static let connectionPollInterval: TimeInterval = 5
    static let connectionPollWindow: TimeInterval = 65
    static let rssiPollDelay: TimeInterval = 5

    static func responseTimeout(for subcode: WiFiGatewayV19Subcode) -> TimeInterval {
        switch subcode {
        case .connectionStatus, .dfuStart, .dfuStatus:
            return 3
        case .rssiStatus:
            return 4
        case .credentialsSet, .credentialsRead, .credentialsClear,
             .firmwareVersion, .dfuCancel:
            return 7
        }
    }
}
