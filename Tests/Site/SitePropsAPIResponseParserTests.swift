import Foundation

enum NetworkApiError: Error {
    case unknown
}

enum NetowrkReqeustApi {
    case sitePropsRetrieve(siteId: String)
    case sitePropsUpdate(siteId: String, props: [String: Any])
}

final class NetworkRequest {
    static let shared = NetworkRequest()

    func request(
        _ target: NetowrkReqeustApi
    ) async -> Result<[String: Any], NetworkApiError> {
        return .failure(.unknown)
    }
}

@main
struct SitePropsAPIResponseParserTests {

    static func main() {
        let client = SitePropsAPIClient(networkRequest: .shared)

        let numericOne = client.parseUpdateResponse(updateData(
            imageId: "1",
            updateTimestamp: "1786778445"
        ))
        require(numericOne?.imageId == 1, "JSON number imageId 1 must parse")
        require(numericOne?.timestamp == 1_786_778_445, "JSON number timestamp must parse")
        require(numericOne?.providedFields == [.imageId], "Image-only response must track imageId")
        require(numericOne?.timezone == nil, "Image-only response must not require timezone")

        let numericZero = client.parseUpdateResponse(updateData(imageId: "0"))
        require(numericZero?.imageId == 0, "JSON number imageId 0 must parse")

        for boolLiteral in ["true", "false"] {
            require(
                client.parseUpdateResponse(updateData(imageId: boolLiteral)) == nil,
                "JSON Bool imageId must be rejected"
            )
            require(
                client.parseUpdateResponse(updateData(updateTimestamp: boolLiteral)) == nil,
                "JSON Bool updateTimestamp must be rejected"
            )
        }

        require(
            client.parseUpdateResponse(updateData(imageId: "1.5")) == nil,
            "Fractional imageId must remain invalid"
        )

        testCoordinateFormats(client: client)
        print("SitePropsAPIResponseParserTests passed")
    }

    private static func testCoordinateFormats(client: SitePropsAPIClient) {
        // Real JSON types, including the coordinate strings returned by Site receipt.
        let fixtures = [
            #"{"latitude":"22.545540","longitude":"114.068300"}"#,
            #"{"latitude":22.545540,"longitude":114.068300}"#,
            #"{"latitude":"22.545540","longitude":114.068300}"#,
            #"{"latitude":22.545540,"longitude":" 114.068300 "}"#
        ]
        for fixture in fixtures {
            var data = try! JSONSerialization.jsonObject(with: Data(fixture.utf8)) as! [String: Any]
            data["updateTimestamp"] = 1
            guard let snapshot = client.parseUpdateResponse(data) else {
                fatalError("Numeric and string coordinates must parse")
            }
            let properties = snapshot.standardProperties.applying(to: .init())
            require(properties.latitude == 22.54554 && properties.longitude == 114.0683,
                    "Coordinate formats must normalize to the same Double values")
            let encoded = try! JSONSerialization.data(withJSONObject: properties.jsonObject)
            let exported = try! JSONSerialization.jsonObject(with: encoded) as! [String: Any]
            require(exported["latitude"] is NSNumber && exported["longitude"] is NSNumber,
                    "Normalized coordinates must export as JSON numbers")
        }

        for (key, bound) in [("latitude", 90.0), ("longitude", 180.0)] {
            let endpoints: [Any] = [bound, -bound, String(bound), String(-bound)]
            for value in endpoints {
                require(client.parseUpdateResponse(["updateTimestamp": 1, key: value]) != nil,
                        "Coordinate endpoints must remain valid in both formats")
            }
            let invalid: [Any] = [true, false, "", " \n", "invalid", "true", "NaN", "Infinity", "1e9999",
                                  Double.nan, Double.infinity, bound + 1, -(bound + 1),
                                  String(bound + 1), String(-(bound + 1)), [1], ["value": 1]]
            for value in invalid {
                require(client.parseUpdateResponse(["updateTimestamp": 1, key: value]) == nil,
                        "Malformed, boolean, non-finite and out-of-range coordinates must be rejected")
            }
        }
        let original = SiteStandardProperties(latitude: 22.54554, longitude: 114.0683)
        let omitted = client.parseUpdateResponse(["updateTimestamp": 1])!
        require(omitted.standardProperties.applying(to: original) == original,
                "Omitted coordinates must preserve the existing values")
        let cleared = client.parseUpdateResponse(["updateTimestamp": 1, "latitude": NSNull(), "longitude": NSNull()])!
        let result = cleared.standardProperties.applying(to: original)
        require(result.latitude == nil && result.longitude == nil, "Explicit null must still clear coordinates")
    }

    private static func updateData(
        imageId: String = "1",
        updateTimestamp: String = "1786778445"
    ) -> [String: Any] {
        let json = """
        {
          "code": 200,
          "data": {
            "imageId": \(imageId),
            "updateTimestamp": \(updateTimestamp)
          },
          "message": "success"
        }
        """

        guard
            let object = try? JSONSerialization.jsonObject(
                with: Data(json.utf8)
            ),
            let response = object as? [String: Any],
            let data = response["data"] as? [String: Any]
        else {
            fatalError("Expected valid Site props update fixture")
        }
        return data
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else { fatalError(message) }
    }
}
