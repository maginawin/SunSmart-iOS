import Foundation

@main
struct SiteTimeSetCallSiteContractTests {

    static func main() throws {
        let arguments = CommandLine.arguments
        require(
            arguments.count == 14,
            "Expected factory, App sources, project, two SDK sources and Space clock coordinator"
        )

        let factory = try source(arguments[1])
        let appSources = try (2...9).map { try source(arguments[$0]) }
        let project = try source(arguments[10])
        let sdkMessages = try source(arguments[11])
        let sdkAPI = try source(arguments[12])
        let combinedAppSources = (appSources + [try source(arguments[13])]).joined(separator: "\n")

        require(
            !matches(#"Node\.setLocalTimeMessage\s*\(\s*\)"#, in: combinedAppSources),
            "Active App sources must not use the phone-timezone TimeSet constructor"
        )
        require(
            !matches(
                #"Node\.makeLocalTimeSetMessageHandle\s*\(\s*model\s*:"#,
                in: combinedAppSources
            ),
            "Active App sources must not bypass the Site TimeSet factory"
        )
        require(
            !matches(
                #"MeshAPI\.syncNodeTime\s*\(\s*address\s*:[^,\)]*\)"#,
                in: combinedAppSources
            ),
            "Debug TimeSet must pass an explicit resolved timezone"
        )
        require(
            combinedAppSources.contains("SiteTimeSetMessageFactory.makeHandle(")
                && combinedAppSources.contains("SiteTimeSetMessageFactory.broadcast(")
                && combinedAppSources.contains("SiteTimeSetMessageFactory.resolve("),
            "All TimeSet variants must route through the shared factory"
        )
        // Connection delay, permission denial, retry and exit behavior now run in
        // check_space_clock_sync.sh instead of matching the old Devices callback text.
        require(
            factory.contains("SiteData.load(siteId: siteID)")
                && factory.contains("snapshot.isUsable(at: date)")
                && factory.contains("SiteTimeSetMessageFactory"),
            "Valid Site zones must use a usable snapshot; phone fallback behavior is tested separately"
        )
        require(
            !matches(#"site\.timezone\s*=(?!=)"#, in: factory)
                && !factory.contains("site.save(")
                && !factory.contains("SiteProps"),
            "The fallback layer must never mutate or upload Site timezone"
        )
        require(
            occurrences(of: "SiteTimeSetMessageFactory.swift", in: project) >= 9,
            "The shared TimeSet factory must belong to all four App targets"
        )
        require(
            !project.contains("EmerFireAlarmSyncCellModel.swift"),
            "The stale Fire Alarm duplicate must remain outside production targets"
        )
        require(
            sdkMessages.contains("ExplicitTimeSetInputProvider(timeZone: timeZone)")
                && sdkMessages.contains("Node.setLocalTimeMessage(input: inputProvider.make())"),
            "The explicit SDK handle must refresh Date while retaining the selected offset"
        )
        require(
            sdkAPI.contains("timeZone: TimeZone")
                && sdkAPI.contains("syncNodeTime(address: address, timeZone: .current"),
            "The SDK must retain explicit and backward-compatible syncNodeTime APIs"
        )

        print("SiteTimeSetCallSiteContractTests passed")
    }

    private static func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private static func matches(_ pattern: String, in source: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            fatalError("Invalid contract regex: \(pattern)")
        }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return expression.firstMatch(in: source, range: range) != nil
    }

    private static func occurrences(of value: String, in source: String) -> Int {
        source.components(separatedBy: value).count - 1
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard condition() else {
            fatalError(message, file: file, line: line)
        }
    }
}
