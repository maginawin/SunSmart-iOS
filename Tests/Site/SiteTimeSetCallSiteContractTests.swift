import Foundation

@main
struct SiteTimeSetCallSiteContractTests {

    static func main() throws {
        let arguments = CommandLine.arguments
        require(
            arguments.count == 13,
            "Expected factory, eight App sources, project and two SDK sources"
        )

        let factory = try source(arguments[1])
        let appSources = try (2...9).map { try source(arguments[$0]) }
        let project = try source(arguments[10])
        let sdkMessages = try source(arguments[11])
        let sdkAPI = try source(arguments[12])
        let combinedAppSources = appSources.joined(separator: "\n")
        let devicesSource = appSources[5]

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
                && combinedAppSources.contains("SiteTimeSetMessageFactory.makeMessage(")
                && combinedAppSources.contains("SiteTimeSetMessageFactory.resolve("),
            "All TimeSet variants must route through the shared factory"
        )
        require(
            matches(
                #"getMeshDistribution\(\)\s*// Visitor 没有修改设备时间的权限\s*guard self\.space\.permission != \.visitor else \{\s*return\s*\}\s*// 延迟3s发送广播节点同步时间消息[^\n]*\s*DispatchQueue\.main\.asyncAfter\(deadline: \.now\(\) \+ 3\)"#,
                in: devicesSource
            ),
            "Owner and Editor entry must schedule all-nodes TimeSet without a Schedule gate, while Visitor must be denied"
        )
        require(
            factory.contains("SiteData.load(siteId: siteID)")
                && factory.contains("phoneFallback(")
                && factory.contains("SiteTimeSetMessageFactory"),
            "The factory must resolve local Site first and provide controlled phone fallback"
        )
        require(
            !factory.contains("site.timezone =")
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
