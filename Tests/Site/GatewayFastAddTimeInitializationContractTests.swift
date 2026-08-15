import Foundation

@main
struct GatewayFastAddTimeInitializationContractTests {

    static func main() throws {
        let arguments = CommandLine.arguments
        require(arguments.count == 5, "Expected helper, Fast Add, ExportData and project paths")
        let helper = try String(contentsOfFile: arguments[1], encoding: .utf8)
        let fastAdd = try String(contentsOfFile: arguments[2], encoding: .utf8)
        let export = try String(contentsOfFile: arguments[3], encoding: .utf8)
        let project = try String(contentsOfFile: arguments[4], encoding: .utf8)

        require(
            helper.contains("SiteTimeSetMessageFactory.resolve(")
                && helper.contains("siteTimeZoneStorageValue: String?")
                && helper.contains("SiteTimeSetMessageFactory.makePlan("),
            "Fast Add must use the shared Site-first Time Set factory"
        )
        require(
            fastAdd.contains("siteTimeZoneStorageValue: self.site.timezone"),
            "Fast Add must pass the raw local Site timezone so invalid values can fall back"
        )
        require(
            !fastAdd.contains("site.timezone ="),
            "Fast Add fallback must not update the local Site timezone"
        )
        require(
            fastAdd.contains("appendMessages.append(initialization.handle)"),
            "Gateway TimeSet must be appended to the Fast Add queue"
        )
        require(
            fastAdd.contains("messageHandle.message is TimeSet"),
            "Fast Add success and failure callbacks must identify the TimeSet handle"
        )
        require(
            fastAdd.contains("appendMessageFailedBack:"),
            "TimeSet transport failure must be handled without rolling back Gateway add"
        )
        require(
            fastAdd.contains("GatewayFastAddTimeInitialization.clearUninitializedTime(on: node)"),
            "Failed or invalid TimeSet must clear both optional Gateway time fields"
        )
        require(
            export.contains("if let timezone = node.timezone {")
                && export.contains("nodeDict.updateValue(timezone.encodeToTzOffset(), forKey: \"timezoneOffset\")")
                && export.contains("nodeDict.updateValue(node.timestamp, forKey: \"timestamp\")"),
            "Cloud export must keep omitting time fields when timezone is nil"
        )
        require(
            occurrences(of: "GatewayFastAddTimeInitialization.swift", in: project) >= 9,
            "Fast Add helper must belong to all four app targets"
        )

        print("GatewayFastAddTimeInitializationContractTests passed")
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
