import Foundation

/// 包内功能可见性规则。只决定入口展示，不授予业务操作权限。
final class FeatureVisibility {
    enum Feature: String, CaseIterable {
        case siteTriggerZone = "sites.site.triggerZone"
    }

    enum BuildMode: String, Decodable, CaseIterable {
        case debug
        case release

        static var current: BuildMode {
            #if DEBUG
            return .debug
            #else
            return .release
            #endif
        }
    }

    struct Rule: Decodable {
        let builds: Set<BuildMode>
        let roles: Set<String>

        private enum CodingKeys: String, CodingKey {
            case builds, roles
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            builds = Set(try container.decode([BuildMode].self, forKey: .builds))
            let values = try container.decode([String].self, forKey: .roles)
            guard values.allSatisfy({ Permission(permissionString: $0) != nil }) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .roles, in: container, debugDescription: "Unknown feature role"
                )
            }
            roles = Set(values)
        }

        func isVisible(build: BuildMode, permission: Permission?) -> Bool {
            guard let permission = permission else { return false }
            return builds.contains(build) && roles.contains(permission.dataString)
        }
    }

    /// 每个子节点独立解码，损坏的规则或分组不会影响其余分支。
    struct Configuration: Decodable {
        private(set) var rules: [String: Rule] = [:]
        private(set) var issues: [String] = []

        private struct Key: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            for key in container.allKeys.sorted(by: { $0.stringValue < $1.stringValue }) {
                let path = (decoder.codingPath + [key]).map(\.stringValue).joined(separator: ".")
                guard !key.stringValue.contains(".") else {
                    issues.append("\(path): use nested feature groups")
                    continue
                }
                do {
                    let childDecoder = try container.superDecoder(forKey: key)
                    let child = try childDecoder.container(keyedBy: Key.self)
                    if child.contains(Key(stringValue: "builds")) || child.contains(Key(stringValue: "roles")) {
                        rules[path] = try Rule(from: childDecoder)
                    } else {
                        let group = try Configuration(from: childDecoder)
                        rules.merge(group.rules) { current, _ in current }
                        issues.append(contentsOf: group.issues)
                    }
                } catch {
                    issues.append("\(path): invalid visibility rule or group")
                }
            }
        }
    }

    static let shared = FeatureVisibility()

    private let configuration: Configuration
    private let build: BuildMode

    /// 构建模式与配置保持不变；每次判断都使用调用方传入的当前资源角色。
    init(build: BuildMode = .current, loadData: () throws -> Data = {
        guard let url = Bundle.main.url(forResource: "debug_features", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }) {
        self.build = build
        do {
            configuration = try JSONDecoder().decode(Configuration.self, from: loadData())
            #if DEBUG
            let missing = Feature.allCases.filter { configuration.rules[$0.rawValue] == nil }
            if !configuration.issues.isEmpty || !missing.isEmpty {
                print("[FeatureVisibility] Invalid or missing rules remain hidden: " +
                      (configuration.issues + missing.map(\.rawValue)).joined(separator: ", "))
            }
            #endif
        } catch {
            configuration = Configuration()
            #if DEBUG
            print("[FeatureVisibility] Cannot load debug_features.json; configured features remain hidden.")
            #endif
        }
    }

    func isVisible(_ feature: Feature, permission: Permission?) -> Bool {
        configuration.rules[feature.rawValue]?.isVisible(build: build, permission: permission) ?? false
    }
}
