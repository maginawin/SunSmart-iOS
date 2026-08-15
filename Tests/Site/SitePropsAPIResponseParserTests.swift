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

        print("SitePropsAPIResponseParserTests passed")
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
