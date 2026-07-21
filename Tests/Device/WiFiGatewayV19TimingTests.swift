import Foundation

@main
struct WiFiGatewayV19TimingTests {
    static func main() {
        let expected: [(WiFiGatewayV19Subcode, TimeInterval)] = [
            (.credentialsSet, 7),
            (.connectionStatus, 3),
            (.rssiStatus, 4),
            (.dfuStart, 3),
            (.dfuStatus, 3),
            (.credentialsRead, 7),
            (.credentialsClear, 7),
            (.firmwareVersion, 7),
            (.dfuCancel, 7)
        ]
        for (subcode, timeout) in expected {
            precondition(WiFiGatewayV19Timing.responseTimeout(for: subcode) == timeout)
        }
        precondition(WiFiGatewayV19Timing.connectionPollInterval == 5)
        precondition(WiFiGatewayV19Timing.connectionPollWindow == 65)
        precondition(WiFiGatewayV19Timing.rssiPollDelay == 5)
        print("WiFiGatewayV19TimingTests passed")
    }
}
