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

        let invalidZone = client.parseUpdateResponse(["updateTimestamp": 1, "timezone": "not a timezone"])
        require(invalidZone?.timezone?.storageValue == "not a timezone", "Invalid timezone must preserve its raw value instead of rejecting other Site properties")
        require(invalidZone?.providedFields.contains(.timezone) == true, "Invalid timezone is still a provided field, not an omitted patch")
        require(invalidZone?.timezone?.isRecognizedTimeZone == false, "Preserved data must not authorize Site clock synchronization")
        testCoordinateFormats(client: client)
        testPostalCodeLimit(client: client)
        print("SitePropsAPIResponseParserTests passed")
    }

    private static func testPostalCodeLimit(client: SitePropsAPIClient) {
        let inputs = ["", "00123", " 00123 "]
            + [31, 32, 33].map { String(repeating: "0", count: $0) }
            + ["中", "👩🏽‍💻", "e\u{301}"].map { String(repeating: $0, count: 33) }
        for input in inputs {
            let expected = String(input.prefix(32))
            let bytes = try! JSONSerialization.data(withJSONObject: ["updateTimestamp": 1, "postalCode": input])
            let data = try! JSONSerialization.jsonObject(with: bytes) as! [String: Any]
            let snapshot = client.parseUpdateResponse(data)!
            require(snapshot.standardProperties.applying(to: .init()).postalCode == expected,
                    "Server Postal Code must retain only the first 32 complete characters")
            let properties = SiteStandardProperties(postalCode: input)
            let exported = try! JSONSerialization.data(withJSONObject: properties.jsonObject)
            let object = try! JSONSerialization.jsonObject(with: exported) as! [String: Any]
            require(object["postalCode"] as? String == expected, "Full upload must cap legacy and bypassed form values")
            require(properties.postalCode == input, "Export must not mutate an in-flight local snapshot")
        }
        let original = SiteStandardProperties(postalCode: "00123")
        let omitted = client.parseUpdateResponse(["updateTimestamp": 1])!
        require(omitted.standardProperties.applying(to: original) == original, "Omitted Postal Code must preserve local data")
        let cleared = client.parseUpdateResponse(["updateTimestamp": 1, "postalCode": NSNull()])!
        require(cleared.standardProperties.applying(to: original).postalCode == nil, "Null must clear Postal Code")
        require(SiteStandardProperties().jsonObject["postalCode"] is NSNull, "Nil must still export null")
        require(client.parseUpdateResponse(["updateTimestamp": 1, "postalCode": 123]) == nil,
                "Truncation must not accept a non-string Postal Code")
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
            require(exported["latitude"] as? String == "22.54554" && exported["longitude"] as? String == "114.0683",
                    "Normalized coordinates must export as JSON strings")
        }

        let original = SiteStandardProperties(latitude: 22.54554, longitude: 114.0683)
        for (key, bound) in [("latitude", 90.0), ("longitude", 180.0)] {
            let endpoints: [Any] = [0, "0", bound, -bound, String(bound), String(-bound)]
            for value in endpoints {
                guard let snapshot = client.parseUpdateResponse(["updateTimestamp": 1, key: value]) else {
                    fatalError("Coordinate endpoints must remain valid in both formats")
                }
                let properties = snapshot.standardProperties.applying(to: original)
                require((key == "latitude" ? properties.latitude : properties.longitude) == Double(String(describing: value)),
                        "Zero and coordinate endpoints must retain their numeric values instead of falling back to nil")
            }
            let invalid: [Any] = [true, false, "", " \n", "invalid", "true", "NaN", "Infinity", "1e9999",
                                  Double.nan, Double.infinity, bound + 1, -(bound + 1),
                                  String(bound + 1), String(-(bound + 1)), [1], ["value": 1]]
            for value in invalid {
                let otherKey = key == "latitude" ? "longitude" : "latitude"
                var data: [String: Any] = ["updateTimestamp": 1, key: value, otherKey: "12.5", "countryRegion": "SG"]
                // Use real JSON decoding for wire-representable values, including booleans.
                // Direct NaN/Infinity values exercise the in-memory defensive boundary.
                if JSONSerialization.isValidJSONObject(data) {
                    let bytes = try! JSONSerialization.data(withJSONObject: data)
                    data = try! JSONSerialization.jsonObject(with: bytes) as! [String: Any]
                }
                guard let snapshot = client.parseUpdateResponse(data) else {
                    fatalError("Invalid coordinates must not reject other Site properties")
                }
                let properties = snapshot.standardProperties.applying(to: original)
                require((key == "latitude" ? properties.latitude : properties.longitude) == nil,
                        "A present invalid coordinate must clear its previous value")
                require((key == "latitude" ? properties.longitude : properties.latitude) == 12.5,
                        "The other valid coordinate must still be applied")
                require(properties.countryRegion == "SG", "Coordinate fallback must not discard unrelated properties")
                require(snapshot.standardProperties.providedFields == [.latitude, .longitude, .countryRegion],
                        "Fallback is an explicit empty value, not an omitted field")
                let bytes = try! JSONSerialization.data(withJSONObject: properties.jsonObject)
                let exported = try! JSONSerialization.jsonObject(with: bytes) as! [String: Any]
                require(exported[key] is NSNull && exported[otherKey] as? String == "12.5",
                        "Fallback must export null while valid coordinates remain strings")
            }
        }
        let omitted = client.parseUpdateResponse(["updateTimestamp": 1])!
        require(omitted.standardProperties.applying(to: original) == original,
                "Omitted coordinates must preserve the existing values")
        let cleared = client.parseUpdateResponse(["updateTimestamp": 1, "latitude": NSNull(), "longitude": NSNull()])!
        let result = cleared.standardProperties.applying(to: original)
        require(result.latitude == nil && result.longitude == nil, "Explicit null must still clear coordinates")
        require(client.parseUpdateResponse(["updateTimestamp": 1, "latitude": "", "cityId": true]) == nil,
                "Coordinate fallback must not relax other standard-field validation")
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
