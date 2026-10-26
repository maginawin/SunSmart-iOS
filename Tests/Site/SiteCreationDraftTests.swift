import Foundation

@main enum SiteCreationDraftTests {
    static func main() throws {
        for (field, limit) in [(SiteCreationTextField.description, 300), (.streetAddress, 300),
                                (.postalCode, 100), (.latitude, 50), (.longitude, 50)] {
            precondition(field.normalized(" \n\t ") == nil)
            precondition(field.normalized("  value \n") == "value")
            precondition(field.limitingInput("value ") == "value ", "Typing a word separator must not trim it away")
            let text = String(repeating: "👩🏽‍💻", count: limit)
            precondition(field.normalized("  " + text + "x  ") == text)
            precondition(field.limitingInput("  " + text + "x  ") == text)
            precondition(field.normalized(String(repeating: "a", count: limit - 1) + " xyz") == String(repeating: "a", count: limit - 1))
        }
        precondition(SiteCreationTextField.description.normalized(" A\nB ") == "A\nB")
        var draft = SiteCreationDraft(siteName: "Site 2", timezone: nil)
        precondition(draft.siteType == .standard)
        let initialObject = try draft.extensionData.jsonObject()
        precondition(initialObject["siteType"] as? String == "Standard")
        precondition(draft.isNameValid(isDuplicate: false))
        precondition(!draft.isNameValid(isDuplicate: true))
        for name in ["", "   ", String(repeating: "x", count: 33)] {
            draft.siteName = name
            precondition(!draft.isNameValid(isDuplicate: false))
        }
        draft.siteName = " Site "
        precondition(draft.isNameValid(isDuplicate: false), "Keep existing name whitespace semantics")
        draft.text[.postalCode] = " 018983 "
        draft.text[.latitude] = " -1.2801 "
        draft.text[.longitude] = " 0 "
        draft.siteType = .hdb
        let object = try draft.standardProperties().jsonObject
        precondition(object["postalCode"] as? String == "018983")
        precondition(object["latitude"] as? Double == -1.2801)
        precondition(object["longitude"] as? Double == 0)
        precondition(object["description"] is NSNull && object["city"] is NSNull && object["countryRegion"] is NSNull)
        let extensionObject = try draft.extensionData.jsonObject()
        precondition(extensionObject["siteType"] as? String == "HDB" && extensionObject["latitude"] == nil)
        precondition(draft.timezone == nil && draft.imageId == 1)

        draft.text[.streetAddress] = "  1 Marina Boulevard "
        draft.text[.description] = " Lobby "
        let mapped = try draft.standardProperties().jsonObject
        precondition(mapped["address"] as? String == "1 Marina Boulevard" && mapped["streetAddress"] == nil)
        precondition(mapped["description"] as? String == "Lobby")
        for field in [SiteCreationTextField.latitude, .longitude] {
            let limit = field == .latitude ? 90.0 : 180.0
            for input in ["", "  ", "0", "-0", "-1.2345", String(limit), String(-limit)] {
                draft.text[field] = input
                _ = try draft.standardProperties()
            }
            for input in ["abc", "-", "1,2", "nan", "inf", "-Infinity", "1e999", String(limit + 0.00001), String(-limit - 0.00001)] {
                draft.text[field] = input
                do {
                    _ = try draft.standardProperties()
                    preconditionFailure("Invalid coordinate must not be silently cleared: \(input)")
                } catch let error as SiteCreationDraft.InvalidCoordinate { precondition(error.field == field) }
                precondition(draft.text[field] == input, "Validation must preserve the draft")
            }
            draft.text[field] = ""
        }
        let cleared = try draft.standardProperties()
        precondition(cleared.latitude == nil && cleared.longitude == nil)
        draft.text[.longitude] = "0"
        let single = try draft.standardProperties()
        precondition(single.latitude == nil && single.longitude == 0)

        let catalog = try SiteTimeZoneCatalog(data: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        precondition(catalog.value(matchingIdentifier: "Asia/Shanghai")?.storageValue == "Asia/Shanghai (UTC+08:00)")
        precondition(catalog.value(matchingIdentifier: "missing/zone") == nil)
        precondition(catalog.value(matchingIdentifier: "GMT+1234") == nil, "Creation must not invent a fallback")
        print("PASS: creation draft normalization, Unicode limits, name validation, numeric coordinates and validation and strict time zone lookup")
    }
}
