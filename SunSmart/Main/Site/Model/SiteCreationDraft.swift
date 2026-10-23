import Foundation

enum SiteCreationTextField: String, CaseIterable {
    case description, streetAddress, postalCode, latitude, longitude

    var maximumLength: Int {
        switch self {
        case .description, .streetAddress: return 300
        case .postalCode: return 100
        case .latitude, .longitude: return 50
        }
    }

    func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(trimmed.prefix(maximumLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Do not trim ordinary keystrokes; preserve spaces while typing a multi-word value.
    func limitingInput(_ text: String) -> String {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).count > maximumLength else { return text }
        return normalized(text) ?? ""
    }
}

/// Transient form values. Constructing or changing a draft never creates a Site or Mesh.
struct SiteCreationDraft {
    var siteName: String
    var timezone: SiteTimeZoneValue?
    var imageId = 1
    var siteType: SiteExtensionData.ProjectType = .standard
    var text: [SiteCreationTextField: String] = [:]

    func isNameValid(isDuplicate: Bool) -> Bool {
        // Match Edit Site's existing ordinary-space and Character-count semantics.
        !siteName.isEmpty && siteName.contains(where: { $0 != " " })
            && siteName.count <= 32 && !isDuplicate
    }

    var extensionData: SiteExtensionData {
        var data = SiteExtensionData()
        data.siteType = siteType
        for key in SiteExtensionData.metadataKeys { data.fields[key] = .null }
        for field in SiteCreationTextField.allCases {
            data.fields[field.rawValue] = field.normalized(text[field] ?? "").map(SiteJSONValue.string) ?? .null
        }
        return data
    }
}
