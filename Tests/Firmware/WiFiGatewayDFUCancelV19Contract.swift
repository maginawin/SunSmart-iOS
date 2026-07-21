import Foundation

@main
struct WiFiGatewayDFUCancelV19Contract {
    static func main() throws {
        let request = try WiFiGatewayDFUCancelRequest(otaID: 0x8877665544332211)
        precondition(
            request.parameters == Data([
                0x43, 0x15, 0x11, 0x22, 0x33,
                0x44, 0x55, 0x66, 0x77, 0x88
            ])
        )
        do {
            _ = try WiFiGatewayDFUCancelRequest(otaID: 0)
            preconditionFailure("zero ota_id must be rejected")
        } catch {
            precondition(error as? WiFiGatewayDFUCancelValidationError == .invalidOTAID)
        }

        let ota = Data([0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88])
        let expected: [(UInt8, WiFiGatewayDFUCancelResult)] = [
            (0x00, .success),
            (0x01, .invalidParameters),
            (0x02, .notCancelled),
            (0x03, .unconfirmed),
            (0x04, .busy),
            (0x7F, .reserved(rawValue: 0x7F))
        ]
        for (raw, result) in expected {
            let response = WiFiGatewayDFUCancelResponseParser.parse(
                Data([0x43, 0x15, raw]) + ota
            )
            precondition(response?.result == result)
            precondition(response?.otaID == 0x8877665544332211)
        }
        precondition(
            WiFiGatewayDFUCancelResponseParser.parse(
                Data([0x43, 0x15, 0x01]) + Data(repeating: 0, count: 8)
            )?.otaID == 0
        )
        precondition(
            WiFiGatewayDFUCancelResponseParser.parse(
                Data([0x43, 0x15, 0x00]) + ota + Data([0])
            ) == nil
        )
        precondition(
            WiFiGatewayDFUCancelResponseMatcher.matches(
                requestOTAID: request.otaID,
                response: WiFiGatewayDFUCancelResponseParser.parse(
                    Data([0x43, 0x15, 0x00]) + ota
                )
            )
        )
        print("WiFiGatewayDFUCancelV19Contract passed")
    }
}
