import Foundation

// 独立测试编译时使用从 SiteData.swift 提取的原始 Permission 定义。
extension String { var localizedString: String { self } }

@main
struct FeatureVisibilityTests {
    static func data(feature: FeatureVisibility.Feature, builds: [String], roles: [String]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["sites": ["site": [feature.rawValue.components(separatedBy: ".").last!: [
            "builds": builds, "roles": roles
        ]]]])
    }

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }

    static func main() throws {
        let builds = [["debug"], ["debug", "release"], ["release"]]
        let roles = [["owner"], ["owner", "editor"], ["owner", "editor", "visitor"]]
        let permissions: [Permission] = [.owner, .editor, .visitor]
        var cases = 0
        for feature in FeatureVisibility.Feature.allCases {
            for allowedBuilds in builds {
                for allowedRoles in roles {
                    let bytes = try data(feature: feature, builds: allowedBuilds, roles: allowedRoles)
                    for build in FeatureVisibility.BuildMode.allCases {
                        var loads = 0
                        let visibility = FeatureVisibility(build: build) { loads += 1; return bytes }
                        for role in permissions {
                            let expected = allowedBuilds.contains(build.rawValue) && allowedRoles.contains(role.dataString)
                            check(visibility.isVisible(feature, permission: role) == expected, "Matrix mismatch")
                            cases += 1
                        }
                        check(!visibility.isVisible(feature, permission: nil), "Missing role must hide")
                        check(loads == 1, "Role changes must reuse configuration")
                    }
                    let current = FeatureVisibility { bytes }
                    for role in permissions {
                        check(current.isVisible(feature, permission: role) ==
                              (allowedBuilds.contains(FeatureVisibility.BuildMode.current.rawValue) && allowedRoles.contains(role.dataString)),
                              "Actual compilation mode mismatch")
                    }
                }
            }
        }
        #if DEBUG
        check(FeatureVisibility.BuildMode.current == .debug, "DEBUG compile flag ignored")
        #else
        check(FeatureVisibility.BuildMode.current == .release, "Release compile flag ignored")
        #endif

        let invalidRules = [
            "{}", "null", "true", "[]", "1", "\"true\"",
            #"{"builds":["debug"]}"#,
            #"{"roles":["owner"]}"#,
            #"{"builds":null,"roles":["owner"]}"#,
            #"{"builds":["debug"],"roles":null}"#,
            #"{"builds":"debug","roles":["owner"]}"#,
            #"{"builds":["debug"],"roles":"owner"}"#,
            #"{"builds":["debug","Debug"],"roles":["owner"]}"#,
            #"{"builds":["debug","beta"],"roles":["owner"]}"#,
            #"{"builds":["debug"],"roles":["owner","admin"]}"#,
            #"{"builds":["debug"],"roles":["Owner"]}"#,
            #"{"builds":["debug",1],"roles":["owner"]}"#,
            #"{"builds":["debug"],"roles":["owner",true]}"#,
            #"{"builds":[],"roles":["owner"]}"#,
            #"{"builds":["debug"],"roles":[]}"#
        ]
        for feature in FeatureVisibility.Feature.allCases {
            for rule in invalidRules {
                let bytes = Data("{\"sites\":{\"site\":{\"\(feature.rawValue.components(separatedBy: ".").last!)\":\(rule)}}}".utf8)
                for build in FeatureVisibility.BuildMode.allCases {
                    let visibility = FeatureVisibility(build: build) { bytes }
                    check(!visibility.isVisible(feature, permission: .owner), "Invalid rule allowed owner: \(rule)")
                }
            }
            for raw in ["{", "[]", "null", "true", "{}", #"{"sites":{}}"#, #"{"sites":{"site":null}}"#,
                        #"{"sites":"invalid"}"#, #"{"sites.site.triggerZone":{"builds":["debug"],"roles":["owner"]}}"#] {
                let visibility = FeatureVisibility(build: .debug) { Data(raw.utf8) }
                check(!visibility.isVisible(feature, permission: .owner), "Malformed/missing hierarchy allowed")
            }
            let unavailable = FeatureVisibility { throw CocoaError(.fileReadNoSuchFile) }
            check(!unavailable.isVisible(feature, permission: .owner), "Missing file allowed")

        }

        let mixed = Data(#"{"sites":{"site":{"triggerZone":{"builds":["debug","debug"],"roles":["owner","owner"],"note":123},"broken":{"builds":["oops"],"roles":["owner"]}},"badGroup":false},"other":{"valid":{"builds":["release"],"roles":["visitor"]}}}"#.utf8)
        let parsed = try JSONDecoder().decode(FeatureVisibility.Configuration.self, from: mixed)
        check(parsed.rules.count == 2 && parsed.issues.count == 2, "Rule errors must stay isolated")
        check(parsed.rules["sites.site.triggerZone"]?.builds.count == 1, "Duplicate values must collapse")
        check(parsed.rules["other.valid"]?.isVisible(build: .release, permission: .visitor) == true, "Sibling rule lost")
        let mixedVisibility = FeatureVisibility(build: .debug) { mixed }
        check(mixedVisibility.isVisible(.siteTriggerZone, permission: .owner), "Unknown rule field changed visibility")

        for brokenFeature in FeatureVisibility.Feature.allCases {
            let goodFeature: FeatureVisibility.Feature = brokenFeature == .siteExportJson ? .siteTriggerZone : .siteExportJson
            let goodKey = goodFeature.rawValue.components(separatedBy: ".").last!
            let badKey = brokenFeature.rawValue.components(separatedBy: ".").last!
            let bytes = try JSONSerialization.data(withJSONObject: ["sites": ["site": [
                goodKey: ["builds": ["debug"], "roles": ["owner", "editor"]],
                badKey: ["builds": ["invalid"], "roles": ["owner"]]
            ]]])
            let visibility = FeatureVisibility(build: .debug) { bytes }
            check(visibility.isVisible(goodFeature, permission: .editor), "Sibling feature must remain visible")
            check(!visibility.isVisible(brokenFeature, permission: .owner), "Broken feature must hide")
        }

        let configURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let bundled = try Data(contentsOf: configURL)
        let config = try JSONDecoder().decode(FeatureVisibility.Configuration.self, from: bundled)
        check(config.issues.isEmpty, "Invalid checked-in configuration: \(config.issues)")
        for feature in FeatureVisibility.Feature.allCases {
            check(config.rules[feature.rawValue] != nil, "Missing known feature: \(feature.rawValue)")
        }
        check(Set(config.rules.keys) == Set(FeatureVisibility.Feature.allCases.map(\.rawValue)), "Unregistered feature path in configuration")
        let checkedInVisibility = FeatureVisibility(build: .debug) { bundled }
        check(checkedInVisibility.isVisible(.siteExportJson, permission: .visitor),
              "Checked-in Debug export rule must allow visitor")
        check(!FeatureVisibility(build: .release, loadData: { bundled }).isVisible(.siteExportJson, permission: .visitor),
              "Checked-in Release export rule must remain hidden")
        print("PASS: \(cases) matrix cases, 54 current-build cases, invalid input, isolation, roles, cache and bundle configuration (\(FeatureVisibility.BuildMode.current.rawValue))")
    }
}
