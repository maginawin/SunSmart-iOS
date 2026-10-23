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
        draft.isHdbSite = true
        let object = try draft.extensionData.jsonObject()
        precondition(object["postalCode"] as? String == "018983")
        precondition(object["latitude"] as? String == "-1.2801")
        precondition(object["longitude"] as? String == "0")
        precondition(object["description"] is NSNull && object["city"] is NSNull && object["countryRegion"] is NSNull)
        precondition(object["isHdbSite"] as? Bool == true)
        precondition(draft.timezone == nil && draft.imageId == 1)

        let catalog = try SiteTimeZoneCatalog(data: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        precondition(catalog.value(matchingIdentifier: "Asia/Shanghai")?.storageValue == "Asia/Shanghai (UTC+08:00)")
        precondition(catalog.value(matchingIdentifier: "missing/zone") == nil)
        precondition(catalog.value(matchingIdentifier: "GMT+1234") == nil, "Creation must not invent a fallback")
        print("PASS: creation draft normalization, Unicode limits, name validation, string coordinates and strict time zone lookup")
    }
}
