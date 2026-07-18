import Foundation

struct TestServerRegion {
    let baseURL: URL
}

enum UserData {
    static let currentServerRegion = TestServerRegion(
        baseURL: URL(string: "https://www.mericher.com/srv2")!
    )
}

@main
struct WiFiFirmwareDFUMetadataBuilderTests {
    static func main() throws {
        let filename = "dev/20260514100245/OTA_Gateway_SS_0A78_0x2721_wifi_9036T-GW-54TA-PA-WIFI_v0.4.0_20260514.zip"
        let url = try WiFiFirmwareDFUMetadataBuilder.makeURL(
            filename: filename,
            baseURL: UserData.currentServerRegion.baseURL
        )
        precondition(
            url == "http://www.mericher.com/srv2/sitespace/ota/download?key=\(filename)"
        )

        for host in [
            "sunsmart-ap.mericher.com",
            "sunsmart-us.mericher.com",
            "sunsmart-eu.mericher.com"
        ] {
            let regionalURL = try WiFiFirmwareDFUMetadataBuilder.makeURL(
                filename: filename,
                baseURL: URL(string: "https://\(host)/srv2")!
            )
            precondition(
                regionalURL == "http://\(host)/srv2/sitespace/ota/download?key=\(filename)"
            )
        }

        let lowercasePrefix = try WiFiFirmwareDFUMetadataBuilder.firmwareID(version: "v0.4.0")
        let uppercasePrefix = try WiFiFirmwareDFUMetadataBuilder.firmwareID(version: "V0.4.0")
        let doublePrefix = try WiFiFirmwareDFUMetadataBuilder.firmwareID(version: "vV0.4.0")
        let noPrefix = try WiFiFirmwareDFUMetadataBuilder.firmwareID(version: "0.4.0")
        precondition(lowercasePrefix == "0.4.0")
        precondition(uppercasePrefix == "0.4.0")
        precondition(doublePrefix == "V0.4.0")
        precondition(noPrefix == "0.4.0")

        print("WiFiFirmwareDFUMetadataBuilderTests passed")
    }
}
