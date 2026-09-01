import Foundation

@main
struct NodeCreatedTimestampContractTests {
    static func main() throws {
        guard CommandLine.arguments.count == 6 else {
            fatalError("Expected Node, MeshDatabase, ExportData, ImportData, and API paths")
        }

        let node = try source(at: 1)
        let database = try source(at: 2)
        let exportData = try source(at: 3)
        let importData = try source(at: 4)
        let api = try source(at: 5)

        require(
            node.contains("public internal(set) var createdTimestamp: Int64 = 0"),
            "Every SDK Node must expose a persisted createdTimestamp with legacy default 0"
        )
        require(
            occurrences(of: "createdTimestamp = Int64(Date().timeIntervalSince1970)", in: node) == 2,
            "Only fresh provisioned and manually-created insecure Nodes should use the phone time"
        )
        require(
            node.contains("self.createdTimestamp = node.createdTimestamp"),
            "Node copy must preserve createdTimestamp"
        )
        require(
            node.contains("public func restoreCreatedTimestamp(_ timestamp: Int64)") &&
                node.contains("createdTimestamp = max(0, timestamp)"),
            "Server imports must use the normalized restore boundary"
        )

        let codingKeys = substring(
            in: node,
            from: "private enum CodingKeys: String, CodingKey",
            through: "case legacyIsBlacklisted"
        )
        require(
            !codingKeys.contains("createdTimestamp"),
            "Generic Node Codable must not change the independent Gateway payload"
        )

        require(
            database.contains("Expression<Int64>(\"createdTimestamp\")") &&
                database.contains("builder.column(ExpressionKey.createdTimestamp, defaultValue: 0)"),
            "The SDK nodes table must define createdTimestamp with legacy default 0"
        )
        require(
            database.contains("$0.name == \"createdTimestamp\"") &&
                database.contains("addColumn(ExpressionKey.createdTimestamp, defaultValue: 0)"),
            "Existing SDK databases must migrate createdTimestamp to 0"
        )
        require(
            database.contains("node.createdTimestamp = row[ExpressionKey.createdTimestamp]") &&
                database.contains("ExpressionKey.createdTimestamp <- self.createdTimestamp"),
            "SDK Node load and save must round-trip createdTimestamp"
        )

        require(
            occurrences(
                of: "nodeDict.updateValue(node.createdTimestamp, forKey: \"createdTimestamp\")",
                in: exportData
            ) == 1,
            "Site and Space must share one createdTimestamp export boundary"
        )
        let independentNodeExport = substring(
            in: exportData,
            from: "extension Node {",
            through: "extension GatewayModel {"
        )
        require(
            !independentNodeExport.contains("createdTimestamp"),
            "Independent Gateway Node export must remain unchanged"
        )

        require(
            occurrences(
                of: "node.restoreCreatedTimestamp(nodeJson[\"createdTimestamp\"].int64 ?? 0)",
                in: importData
            ) == 2,
            "Space and Site Node imports must normalize missing and null values to 0"
        )
        require(
            importData.contains("let remoteCreatedTimestamp = JSON(gatewayData)[\"createdTimestamp\"]") &&
                importData.contains(".flatMap { $0 >= 0 ? $0 : nil }") &&
                importData.contains("if let remoteCreatedTimestamp,") &&
                importData.contains("cacheNode.restoreCreatedTimestamp(remoteCreatedTimestamp)") &&
                importData.contains("if nodeChanged {\n                            cacheNode.save()"),
            "Site Gateway merge may only persist an explicit valid creation timestamp"
        )
        require(
            importData.contains("if remoteCreatedTimestamp == nil, let cacheNode {") &&
                importData.contains(
                    "serverNode.restoreCreatedTimestamp(cacheNode.createdTimestamp)"
                ),
            "Site Gateway replacement must preserve the cached timestamp when the field is absent"
        )

        require(
            !api.localizedCaseInsensitiveContains("nodeprops"),
            "This App must not add a nodeprops route"
        )

        print("NodeCreatedTimestampContractTests passed")
    }

    private static func source(at index: Int) throws -> String {
        try String(contentsOfFile: CommandLine.arguments[index], encoding: .utf8)
    }

    private static func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    private static func substring(in text: String, from start: String, through end: String) -> String {
        guard let startRange = text.range(of: start),
              let endRange = text.range(of: end, range: startRange.upperBound..<text.endIndex) else {
            return ""
        }
        return String(text[startRange.lowerBound..<endRange.upperBound])
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            fatalError(message)
        }
    }
}
