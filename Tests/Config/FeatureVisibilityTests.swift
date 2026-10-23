import Foundation

// 独立测试编译时使用从 SiteData.swift 提取的原始 Permission 定义。
extension String { var localizedString: String { self } }

@main
struct FeatureVisibilityTests {
    static func data(feature: FeatureVisibility.Feature, builds: [String], roles: [String]) throws -> Data {
        try JSONSerialization.data(withJSONObject: nested(feature, rule: [
            "builds": builds, "roles": roles
        ]))
    }

    static func nested(_ feature: FeatureVisibility.Feature, rule: Any) -> [String: Any] {
        var value = rule
        for key in feature.rawValue.components(separatedBy: ".").reversed() {
            value = [key: value]
        }
        return value as! [String: Any]
    }

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }

    static func main() throws {
        let targetNames = try String(contentsOfFile: CommandLine.arguments[3], encoding: .utf8)
            .split(separator: "\n").map(String.init)
        // A target restriction must never be silently ignored.
        let noTargets = Data(#"{"sites":{"site":{"triggerZone":{"builds":["debug"],"roles":["owner"],"targets":[]}}}}"#.utf8)
        check(!FeatureVisibility(build: .debug, loadData: { noTargets }).isVisible(.siteTriggerZone, permission: .owner),
              "Empty targets must hide the feature")
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
                let ruleObject = try JSONSerialization.jsonObject(with: Data(rule.utf8), options: .fragmentsAllowed)
                let bytes = try JSONSerialization.data(withJSONObject: nested(feature, rule: ruleObject))
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
            let good = nested(goodFeature, rule: ["builds": ["debug"], "roles": ["owner", "editor"]])
            let bad = nested(brokenFeature, rule: ["builds": ["invalid"], "roles": ["owner"]])
            let goodSite = (good["sites"] as! [String: Any])["site"] as! [String: Any]
            let badSite = (bad["sites"] as! [String: Any])["site"] as! [String: Any]
            let bytes = try JSONSerialization.data(withJSONObject: ["sites": ["site": goodSite.merging(badSite) { _, new in new }]])
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

        for target in targetNames {
            for build in FeatureVisibility.BuildMode.allCases {
                let visibility = FeatureVisibility(build: build, target: target) { bundled }
                for permission in permissions {
                    check(visibility.isVisible(.spaceHDBConfiguration, permission: permission) ==
                          (permission != .visitor), "HDB target/build/role mismatch")
                    check(visibility.isVisible(.siteExportJson, permission: permission) == (build == .debug),
                          "Omitted targets must retain all-brand export behavior")
                    check(visibility.isVisible(.siteTriggerZone, permission: permission) ==
                          (build == .debug && permission != .visitor), "Existing Site Trigger Zone behavior changed")
                }
            }
        }
        let targetCases: [(configured: [String]?, visible: Set<String>)] = [
            (nil, Set(targetNames)),
            (["SunSmart"], ["SunSmart"]),
            (["HSmart"], ["HSmart"]),
            (["Future Brand"], ["Future Brand"]),
            (["SunSmart", "Future Brand"], ["SunSmart", "Future Brand"]),
            (["Archipelago", "SLG Sync Plus"], ["Archipelago", "SLG Sync Plus"]),
            ([], [])
        ]
        for testCase in targetCases {
            var rule: [String: Any] = ["builds": ["debug", "release"], "roles": ["owner"]]
            if let targets = testCase.configured { rule["targets"] = targets }
            let bytes = try JSONSerialization.data(withJSONObject: nested(.spaceHDBConfiguration, rule: rule))
            for target in targetNames {
                for build in FeatureVisibility.BuildMode.allCases {
                    let visibility = FeatureVisibility(build: build, target: target) { bytes }
                    check(visibility.isVisible(.spaceHDBConfiguration, permission: .owner) == testCase.visible.contains(target),
                          "Omitted targets must allow all; specified targets must allow only listed brands")
                }
            }
        }
        for targets: Any in [NSNull(), "SunSmart", ["sunSmart"], ["Unknown"], [1], []] {
            let bytes = try JSONSerialization.data(withJSONObject: ["sites": ["site": [
                "triggerZone": ["builds": ["debug"], "roles": ["owner"], "targets": targets],
                "exportJson": ["builds": ["debug"], "roles": ["owner"]]
            ]]])
            let visibility = FeatureVisibility(build: .debug, target: "SunSmart") { bytes }
            check(!visibility.isVisible(.siteTriggerZone, permission: .owner), "Malformed, unmatched or empty targets must hide")
            check(visibility.isVisible(.siteExportJson, permission: .owner), "Invalid targets affected sibling rule")
        }
        // Creation is gated only by the package environment, regardless of placeholder roles.
        for roles in [[], ["visitor"], ["owner", "editor"]] {
            for builds in [[], ["debug"], ["release"], ["debug", "release"]] {
                let bytes = try JSONSerialization.data(withJSONObject: nested(.siteTypeSelection, rule: [
                    "builds": builds, "roles": roles, "targets": ["SunSmart"]
                ]))
                for target in targetNames {
                    for build in FeatureVisibility.BuildMode.allCases {
                        let visibility = FeatureVisibility(build: build, target: target) { bytes }
                        check(visibility.canSelectSiteType == (target == "SunSmart" && builds.contains(build.rawValue)),
                              "Site creation must ignore placeholder roles")
                    }
                }
            }
        }
        check(!FeatureVisibility { Data("{}".utf8) }.canSelectSiteType, "Missing creation rule must disable selection")
        let rawConfiguration = try JSONSerialization.jsonObject(with: bundled) as! [String: Any]
        let siteRules = (rawConfiguration["sites"] as! [String: Any])["site"] as! [String: Any]
        let typeRule = siteRules["isHdbSite"] as! [String: Any]
        let allowedTargets = typeRule["targets"] as? [String]
        let allowedBuilds = typeRule["builds"] as! [String]
        let allowedRoles = typeRule["roles"] as! [String]
        for target in targetNames {
            for build in FeatureVisibility.BuildMode.allCases {
                let expected = allowedBuilds.contains(build.rawValue) && (allowedTargets?.contains(target) ?? true)
                let visibility = FeatureVisibility(build: build, target: target) { bundled }
                check(visibility.canSelectSiteType == expected, "Site type must follow the current JSON configuration")
                for permission in permissions {
                    check(visibility.isVisible(.siteTypeSelection, permission: permission) ==
                          (expected && allowedRoles.contains(permission.dataString)),
                          "Site type target/build/role mismatch")
                }
            }
        }
        let restricted = try JSONSerialization.data(withJSONObject: nested(.siteTypeSelection, rule: [
            "builds": ["debug", "release"], "roles": ["owner"], "targets": ["Future Brand"]
        ]))
        check(!FeatureVisibility(target: nil) { restricted }.canSelectSiteType,
              "Missing package target must not allow a restricted feature")
        let unrestricted = try data(feature: .siteTypeSelection, builds: ["debug", "release"], roles: ["owner"])
        check(FeatureVisibility(target: nil) { unrestricted }.canSelectSiteType,
              "Omitted targets must retain unrestricted behavior")
        let currentTarget = CommandLine.arguments[2]
        check(FeatureVisibility.currentTarget == currentTarget, "Package target metadata ignored")
        check(FeatureVisibility { bundled }.canSelectSiteType ==
              (allowedBuilds.contains(FeatureVisibility.BuildMode.current.rawValue) && (allowedTargets?.contains(currentTarget) ?? true)),
              "Default visibility must match the actual package target")
        check(checkedInVisibility.isVisible(.spaceHDBConfiguration, permission: .owner) == true,
              "Unrestricted HDB rule must allow the current package target")
        print("PASS: \(cases) matrix cases, current build/target, invalid input, isolation, roles, cache and bundle configuration (\(FeatureVisibility.BuildMode.current.rawValue), \(currentTarget))")
    }
}
