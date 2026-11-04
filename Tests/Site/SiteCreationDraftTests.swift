import Foundation

@main enum SiteCreationDraftTests {
    static func main() throws {
        try testEditingDraft()
        try testCoordinateValidation()
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
        var draft = SiteFormDraft(siteName: "Site 2", timezone: nil)
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
        precondition(object["latitude"] as? String == "-1.2801")
        precondition(object["longitude"] as? String == "0.0")
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
                } catch let error as SiteFormDraft.InvalidCoordinate { precondition(error.field == field) }
                precondition(draft.text[field] == input, "Validation must preserve the draft")
            }
            draft.text[field] = ""
        }
        let cleared = try draft.standardProperties()
        precondition(cleared.latitude == nil && cleared.longitude == nil)
        draft.text[.longitude] = "0"
        let single = try draft.standardProperties()
        precondition(single.latitude == nil && single.longitude == 0)

        var gps = SiteFormDraft(siteName: "GPS", timezone: nil)
        gps.text[.latitude] = "old latitude"
        gps.text[.longitude] = "old longitude"
        precondition(!gps.applyCurrentLocation(latitude: 1, longitude: .infinity))
        precondition(gps.text[.latitude] == "old latitude" && gps.text[.longitude] == "old longitude")
        precondition(gps.applyCurrentLocation(latitude: -0.0000001, longitude: -123.1234567))
        precondition(gps.text[.latitude] == "0" && gps.text[.longitude] == "-123.123457")
        precondition(gps.coordinateSources[.latitude] == .manual && gps.coordinateSources[.longitude] == .manual)
        let gpsProperties = try gps.standardProperties()
        precondition(gpsProperties.longitude == -123.123457)

        let catalog = try SiteTimeZoneCatalog(data: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        precondition(catalog.value(matchingIdentifier: "Asia/Shanghai")?.storageValue == "Asia/Shanghai")
        precondition(catalog.value(matchingIdentifier: "missing/zone") == nil)
        precondition(catalog.value(matchingIdentifier: "GMT+1234") == nil, "Creation must not invent a fallback")
        print("PASS: creation draft normalization, Unicode limits, name validation, coordinate feedback/submission consistency and strict time zone lookup")
    }

    static func testEditingDraft() throws {
        let properties = SiteStandardProperties(latitude: 0, longitude: -0.123456789,
            countryRegion: "legacy country", postalCode: " 00123 ", city: "unlisted-city",
            address: " " + String(repeating: "x", count: 310), siteDescription: "  old text  ")
        var draft = SiteFormDraft(values: .init(siteName: "Existing", imageId: 0, timezone: nil),
                                  properties: properties, siteType: .hdb)
        let hydrated = try draft.standardProperties()
        precondition(hydrated == properties, "Opening/DONE must preserve untouched legacy text and unknown city")
        precondition(draft.imageId == 0 && draft.siteType == .hdb && draft.timezone == nil)
        precondition(draft.city == nil && draft.cityID == nil && draft.cityName == "unlisted-city")
        draft.editText(.description, value: "  changed ")
        draft.editText(.postalCode, value: "00012")
        draft.editText(.longitude, value: "")
        let updated = try draft.standardProperties()
        precondition(updated.siteDescription == "changed" && updated.postalCode == "00012" && updated.longitude == nil)
        precondition(updated.address == properties.address && updated.city == properties.city && updated.latitude == 0)
        let empty = SiteFormDraft(values: .init(siteName: "Old Site", imageId: 1, timezone: nil), properties: .init(), siteType: .standard)
        let emptyProperties = try empty.standardProperties()
        precondition(emptyProperties == .init())
        precondition(empty.isNameValid(isDuplicate: false))
        for valid in [true, false] {
            for error in [true, false] {
                for committing in [true, false] {
                    let enabled = SiteFormDraft.canSubmit(isNameValid: valid, showsCoordinateError: error, isCommitting: committing)
                    precondition(enabled == (valid && !error && !committing))
                }
            }
        }
        print("PASS: existing form hydration, legacy text/city preservation, field clears and shared submit policy")
    }

    static func testCoordinateValidation() throws {
        var draft = SiteFormDraft(siteName: "Coordinates", timezone: nil)
        for field in [SiteCreationTextField.latitude, .longitude] {
            let boundary = field == .latitude ? 90.0 : 180.0
            let examples: [(String, SiteFormDraft.CoordinateValidation)] = [
                ("", .empty), (" \t\n ", .empty), (" 0 ", .valid(0)), ("-0", .valid(0)),
                (" -1.25\n", .valid(-1.25)), ("1e1", .valid(10)),
                (" \(boundary) ", .valid(boundary)), ("\(-boundary)", .valid(-boundary)),
                ("\(boundary + 0.00001)", .outOfRange), (" \(-boundary - 0.00001) ", .outOfRange),
                ("abc", .invalidNumber), ("-", .invalidNumber), ("1,2", .invalidNumber),
                ("NaN", .invalidNumber), ("inf", .invalidNumber), ("-Infinity", .invalidNumber),
                ("1e999", .invalidNumber)
            ]
            for (input, expected) in examples {
                draft.editText(field, value: input)
                precondition(draft.coordinateValidation(for: field) == expected, "Unexpected feedback for \(field): \(input)")
                switch expected {
                case .empty, .valid:
                    let properties = try draft.standardProperties()
                    let actual = field == .latitude ? properties.latitude : properties.longitude
                    if case .valid(let value) = expected { precondition(actual == value) }
                    else { precondition(actual == nil) }
                case .invalidNumber, .outOfRange:
                    do {
                        _ = try draft.standardProperties()
                        preconditionFailure("CREATE must reject the value reported as invalid")
                    } catch let error as SiteFormDraft.InvalidCoordinate { precondition(error.field == field) }
                }
                precondition(draft.text[field] == input && draft.coordinateSources[field] == .manual)
            }
            draft.editText(field, value: "")
        }

        draft.editText(.latitude, value: "91")
        draft.editText(.longitude, value: "abc")
        precondition(draft.coordinateValidation(for: .latitude) == .outOfRange)
        precondition(draft.coordinateValidation(for: .longitude) == .invalidNumber,
                     "Longitude feedback must remain available when latitude also fails")
        precondition(!draft.applyCurrentLocation(latitude: .infinity, longitude: 1))
        precondition(draft.coordinateValidation(for: .latitude) == .outOfRange)
        precondition(draft.coordinateValidation(for: .longitude) == .invalidNumber)
        precondition(draft.applyCurrentLocation(latitude: 1.25, longitude: -2.5))
        precondition(draft.coordinateValidation(for: .latitude) == .valid(1.25))
        precondition(draft.coordinateValidation(for: .longitude) == .valid(-2.5))
    }
}
