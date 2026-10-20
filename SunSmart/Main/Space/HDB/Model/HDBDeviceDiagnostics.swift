import Foundation

enum HDBDiagnosticKind: String, Codable, CaseIterable {
    case subscriptions, publication
    var title: String { ("hdb_diag_" + rawValue).localizedString }
}

struct HDBDiagnosticPublication: Codable, Equatable {
    var address: UInt16
    var keyIndex: UInt16
    var credentials: Int
    var ttl: UInt8
    var periodSteps: UInt8
    var periodResolution: UInt8
    var retransmitCount: UInt8
    var retransmitInterval: UInt16

    static let disabled = Self(address: 0, keyIndex: 0, credentials: 0, ttl: 0,
        periodSteps: 0, periodResolution: 0, retransmitCount: 0, retransmitInterval: 50)

    var fields: [(String, String)] {
        guard address != 0 else { return [("hdb_diag_address", "hdb_diag_disabled".localizedString)] }
        return [("hdb_diag_address", HDBDiagnosticPolicy.hex(address)),
                ("hdb_diag_key_index", String(keyIndex)),
                ("hdb_diag_credentials", String(credentials)),
                ("hdb_diag_ttl", ttl == 0xFF ? "hdb_diag_default_ttl".localizedString : String(ttl)),
                ("hdb_diag_period", "\(periodSteps) / \(periodResolution)"),
                ("hdb_diag_retransmit", "\(retransmitCount) / \(retransmitInterval) ms")]
    }
    var text: String { fields.map { "\($0.0.localizedString): \($0.1)" }.joined(separator: "\n") }

    func differences(from other: Self) -> [String] {
        if address == 0 && other.address == 0 { return [] }
        if address == 0 || other.address == 0 { return ["hdb_diag_address"] }
        return [("hdb_diag_address", address != other.address), ("hdb_diag_key_index", keyIndex != other.keyIndex),
                ("hdb_diag_credentials", credentials != other.credentials), ("hdb_diag_ttl", ttl != other.ttl),
                ("hdb_diag_period", periodSteps != other.periodSteps || periodResolution != other.periodResolution),
                ("hdb_diag_retransmit", retransmitCount != other.retransmitCount || retransmitInterval != other.retransmitInterval)]
            .filter { $0.1 }.map { $0.0 }
    }
}

struct HDBDiagnosticModelSnapshot: Codable, Equatable {
    let target: HDBModelTarget
    let elementIndex: Int
    let sensorProperty: UInt16?
    let savedSubscriptions: [UInt16]?
    let savedPublication: HDBDiagnosticPublication
    let savedLabels: [String]
    let baselineIssue: String?
    let expectedSubscriptions: [UInt16]?
    let exactSubscriptions: Bool
    let subscriptionIssue: String?
    let expectedPublication: HDBDiagnosticPublication?
    let publicationIssue: String?

    var title: String {
        let modelID = String(format: target.companyIdentifier == nil ? "%04X" : "%08X", target.modelId)
        return String(format: "hdb_diag_model_title".localizedString, elementIndex,
                      HDBDiagnosticPolicy.hex(target.elementAddress), modelID)
    }
    var contextText: String {
        var parts = [("hdb_diag_model_" + String(format: "%08X", target.modelId)).localizedString,
                     (target.modelId == 0x1100 ? "hdb_diag_preparation" : "hdb_diag_zone_preparation").localizedString]
        if target.modelId == 0x1100 {
            let names: [UInt16: String] = [0x004D: "hdb_diag_presence", 0x004E: "hdb_diag_ambient", 0x0072: "hdb_diag_energy"]
            let property = sensorProperty.flatMap { id -> String? in
                guard id != 0 else { return nil }
                return names[id].map { "\($0.localizedString) (\(HDBDiagnosticPolicy.hex(id)))" } ?? HDBDiagnosticPolicy.hex(id)
            } ?? "hdb_diag_unknown".localizedString
            parts.append(String(format: "hdb_diag_sensor_property".localizedString,
                                property))
        }
        return parts.joined(separator: " · ")
    }
}

struct HDBDiagnosticResult: Codable, Equatable {
    enum State: String, Codable {
        case notRead, reading, matches, different, unsupported, failed, cancelled, changed
        var title: String { ("hdb_diag_state_" + rawValue).localizedString }
        var completed: Bool { self == .matches || self == .different || self == .unsupported || self == .failed }
    }
    var state: State = .notRead
    var subscriptions: [UInt16]?
    var publication: HDBDiagnosticPublication?
    var statusCode: UInt8?
    var errorKey: String?
    var readAt: Date?
}

struct HDBDiagnosticRow: Codable, Equatable {
    let snapshot: HDBDiagnosticModelSnapshot
    var subscriptions = HDBDiagnosticResult()
    var publication = HDBDiagnosticResult()

    subscript(kind: HDBDiagnosticKind) -> HDBDiagnosticResult {
        get { kind == .subscriptions ? subscriptions : publication }
        set { if kind == .subscriptions { subscriptions = newValue } else { publication = newValue } }
    }

    var summary: String {
        var lines = [snapshot.contextText, "\(HDBDiagnosticKind.subscriptions.title): \(subscriptions.state.title)",
                     "\(HDBDiagnosticKind.publication.title): \(publication.state.title)"]
        let requirements = HDBDiagnosticKind.allCases.compactMap(requirementsMet)
        if !requirements.isEmpty {
            lines.append((requirements.contains(false) ? "hdb_diag_requirements_missing" : "hdb_diag_requirements_met").localizedString)
        }
        if snapshot.target.modelId == 0x1100, let issue = snapshot.publicationIssue { lines.append(issue.localizedString) }
        return lines.joined(separator: "\n")
    }

    func requirementsMet(_ kind: HDBDiagnosticKind) -> Bool? {
        if kind == .subscriptions, let expected = snapshot.expectedSubscriptions, let actual = subscriptions.subscriptions {
            let observed = Set(HDBDiagnosticPolicy.normalized(actual))
            return snapshot.exactSubscriptions ? Set(expected) == observed : Set(expected).isSubset(of: observed)
        }
        if kind == .publication, let expected = snapshot.expectedPublication, let actual = publication.publication {
            return actual.differences(from: expected).isEmpty
        }
        return nil
    }

    func detail(_ kind: HDBDiagnosticKind) -> String {
        let result = self[kind]
        var lines = ["\(kind.title): \(result.state.title)"]
        if let code = result.statusCode { lines.append(String(format: "hdb_diag_status_code".localizedString, Int(code))) }
        if let issue = result.errorKey { lines.append(issue.localizedString) }
        if let issue = snapshot.baselineIssue { lines.append(issue.localizedString) }
        let saved: String, actual: String
        var differences: [String] = []
        var expectedText: String?
        let requirementMet = requirementsMet(kind)
        let issue: String?
        if kind == .subscriptions {
            saved = snapshot.savedSubscriptions.map(HDBDiagnosticPolicy.addresses) ?? "hdb_diag_no_baseline".localizedString
            actual = result.subscriptions.map(HDBDiagnosticPolicy.addresses) ?? "hdb_diag_no_observation".localizedString
            if let app = snapshot.savedSubscriptions, let device = result.subscriptions {
                let observed = Set(HDBDiagnosticPolicy.normalized(device))
                let missing = Set(app).subtracting(observed), extra = observed.subtracting(app)
                if !missing.isEmpty { differences.append("\("hdb_diag_missing".localizedString): \(HDBDiagnosticPolicy.addresses(Array(missing)))") }
                if !extra.isEmpty { differences.append("\("hdb_diag_extra".localizedString): \(HDBDiagnosticPolicy.addresses(Array(extra)))") }
            }
            expectedText = snapshot.expectedSubscriptions.map(HDBDiagnosticPolicy.addresses)
            issue = snapshot.subscriptionIssue
        } else {
            saved = snapshot.savedPublication.text
            actual = result.publication?.text ?? "hdb_diag_no_observation".localizedString
            differences = result.publication?.differences(from: snapshot.savedPublication).map { $0.localizedString } ?? []
            expectedText = snapshot.expectedPublication?.text
            issue = snapshot.publicationIssue
        }
        lines += ["\("hdb_diag_saved".localizedString):\n\(saved)", "\("hdb_diag_actual".localizedString):\n\(actual)"]
        if !differences.isEmpty { lines.append("\("hdb_diag_differences".localizedString):\n" + differences.joined(separator: "\n")) }
        if let issue { lines.append(issue.localizedString) }
        if let expectedText { lines.append("\("hdb_diag_expected".localizedString):\n\(expectedText)") }
        if let requirementMet {
            lines.append((requirementMet ? "hdb_diag_requirements_met" : "hdb_diag_requirements_missing").localizedString)
        }
        if !snapshot.savedLabels.isEmpty { lines.append("hdb_diag_label_limit".localizedString) }
        return lines.joined(separator: "\n")
    }
}

enum HDBDiagnosticPolicy {
    static func includes(_ target: HDBModelTarget) -> Bool {
        HDBLightingZonePolicy.isZoneTarget(target) || [0x1100, 0x1306].contains(target.modelId)
    }
    static func hex(_ address: UInt16) -> String { String(format: "0x%04X", address) }
    static func normalized(_ addresses: [UInt16]) -> [UInt16] { Set(addresses.filter { $0 != 0xFFFF }).sorted() }
    static func addresses(_ values: [UInt16]) -> String {
        values.isEmpty ? "hdb_diag_empty".localizedString : normalized(values).map(hex).joined(separator: ", ")
    }
    static func received(_ values: [UInt16], saved: [UInt16]?) -> HDBDiagnosticResult {
        .init(state: saved.map { Set(normalized($0)) == Set(normalized(values)) ? .matches : .different } ?? .failed,
              subscriptions: values, errorKey: saved == nil ? "hdb_diag_no_baseline" : nil, readAt: Date())
    }
    static func received(_ value: HDBDiagnosticPublication, saved: HDBDiagnosticPublication) -> HDBDiagnosticResult {
        .init(state: value.differences(from: saved).isEmpty ? .matches : .different, publication: value, readAt: Date())
    }
    static func rejected(_ code: UInt8) -> HDBDiagnosticResult {
        .init(state: code == 0x08 || code == 0x0A ? .unsupported : .failed, statusCode: code, readAt: Date())
    }
}
