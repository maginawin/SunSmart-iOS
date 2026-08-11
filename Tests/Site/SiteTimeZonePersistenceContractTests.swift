import Foundation

@main
struct SiteTimeZonePersistenceContractTests {

    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 || arguments.count == 6 else {
            fatalError("Expected persistence paths, optionally followed by lifecycle paths")
        }

        let siteData = try String(contentsOfFile: arguments[1], encoding: .utf8)
        let database = try String(contentsOfFile: arguments[2], encoding: .utf8)

        require(siteData.contains("var timezone: String?"), "SiteData must persist timezone")
        require(
            siteData.contains("var pendingSitePropsMask: SitePropsFieldMask"),
            "SiteData must persist the pending props mask"
        )
        require(
            siteData.contains("var pendingSitePropsTimestamp: Int64?"),
            "SiteData must persist the pending props timestamp"
        )
        require(
            siteData.contains("trimmingCharacters(in: .whitespacesAndNewlines)"),
            "SiteData must normalize empty timezone strings"
        )
        require(
            siteData.contains("site.timezone = self.timezone") &&
                siteData.contains("site.pendingSitePropsMask = self.pendingSitePropsMask") &&
                siteData.contains("site.pendingSitePropsTimestamp = self.pendingSitePropsTimestamp"),
            "SiteData.copy() must preserve timezone and pending metadata"
        )

        require(
            database.contains("Expression<String?>(\"timezone\")") &&
                database.contains("Expression<Int>(\"pendingSitePropsMask\")") &&
                database.contains("Expression<Int64?>(\"pendingSitePropsTimestamp\")"),
            "The sites table must define all new SQLite expressions"
        )

        require(
            occurrences(of: "builder.column(ExpressionKey.timezone)", in: database) == 1 &&
                occurrences(of: "builder.column(ExpressionKey.pendingSitePropsMask", in: database) == 1 &&
                occurrences(of: "builder.column(ExpressionKey.pendingSitePropsTimestamp)", in: database) == 1,
            "The sites create path must include all new columns exactly once"
        )

        require(
            database.contains("$0.name == \"timezone\"") &&
                database.contains("addColumn(ExpressionKey.timezone)") &&
                database.contains("$0.name == \"pendingSitePropsMask\"") &&
                database.contains("addColumn(ExpressionKey.pendingSitePropsMask, defaultValue: 0)") &&
                database.contains("$0.name == \"pendingSitePropsTimestamp\"") &&
                database.contains("addColumn(ExpressionKey.pendingSitePropsTimestamp)"),
            "Old databases must migrate each new column independently"
        )

        require(
            occurrences(of: "timezone = row[ExpressionKey.timezone]", in: database) == 2,
            "Both loadAll and load(siteId:) must restore timezone"
        )
        require(
            occurrences(of: "pendingSitePropsMask = .init(rawValue: row[ExpressionKey.pendingSitePropsMask])", in: database) == 2,
            "Both load paths must restore pending fields"
        )
        require(
            occurrences(of: "pendingSitePropsTimestamp = row[ExpressionKey.pendingSitePropsTimestamp]", in: database) == 2,
            "Both load paths must restore the pending timestamp"
        )

        require(
            database.contains("ExpressionKey.timezone <- self.timezone") &&
                database.contains("ExpressionKey.pendingSitePropsMask <- self.pendingSitePropsMask.rawValue") &&
                database.contains("ExpressionKey.pendingSitePropsTimestamp <- self.pendingSitePropsTimestamp"),
            "SiteData.save() must write timezone and pending metadata"
        )

        require(
            !siteData.contains("sitePropsCloudVersion") &&
                !database.contains("sitePropsCloudVersion"),
            "Do not introduce a second cloud version timestamp"
        )

        if arguments.count == 6 {
            let meshNetwork = try String(contentsOfFile: arguments[3], encoding: .utf8)
            let exportData = try String(contentsOfFile: arguments[4], encoding: .utf8)
            let importData = try String(contentsOfFile: arguments[5], encoding: .utf8)

            require(
                meshNetwork.contains("site.timezone = SiteTimeZoneCatalog.phoneDefaultValue().storageValue"),
                "New Sites must receive the phone timezone before first save"
            )
            require(
                database.contains("if site.timezone == nil") &&
                    database.contains("site.timezone = SiteTimeZoneCatalog.phoneDefaultValue().storageValue") &&
                    database.contains("site.pendingSitePropsMask = []") &&
                    database.contains("site.pendingSitePropsTimestamp = nil"),
                "Clones must inherit or default timezone and reset pending metadata"
            )

            require(
                exportData.contains("SiteTimeZoneValue(storageValue: timezone)") &&
                    exportData.contains("siteJsonData.updateValue(timezoneValue.storageValue, forKey: \"timezone\")"),
                "Whole Site export must include only a valid full timezone value"
            )
            require(
                !exportData.contains("pendingSitePropsMask") &&
                    !exportData.contains("pendingSitePropsTimestamp"),
                "Pending metadata must never be exported"
            )

            require(
                importData.contains("if let timezone = json[\"timezone\"].string") &&
                    importData.contains("SiteTimeZoneValue(storageValue: timezone)") &&
                    importData.contains("self.timezone = timezoneValue.storageValue"),
                "Whole Site import must accept only a valid nonempty timezone"
            )
            require(
                !importData.contains("pendingSitePropsMask") &&
                    !importData.contains("pendingSitePropsTimestamp"),
                "Cloud import must not create or clear Edit Site pending metadata"
            )
        }

        print("SiteTimeZonePersistenceContractTests passed")
    }

    private static func occurrences(of needle: String, in text: String) -> Int {
        return text.components(separatedBy: needle).count - 1
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
