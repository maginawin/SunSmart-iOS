//
//  SiteTimeZoneValue.swift
//  SunSmart
//
//  Created by One on 2026/8/11.
//

import Foundation

struct SiteTimeZoneValue: Hashable {

    let ianaId: String
    let offsetMinutes: Int

    init?(storageValue: String) {
        let value = storageValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(.+?) \(UTC([+-])(\d{2}):(\d{2})\)$"#
        guard let match = Self.match(pattern: pattern, in: value),
              let ianaRange = Range(match.range(at: 1), in: value),
              let signRange = Range(match.range(at: 2), in: value),
              let hourRange = Range(match.range(at: 3), in: value),
              let minuteRange = Range(match.range(at: 4), in: value) else {
            return nil
        }

        let rawOffset = String(value[signRange])
            + String(value[hourRange])
            + ":"
            + String(value[minuteRange])
        self.init(ianaId: String(value[ianaRange]), rawUTCOffset: rawOffset)
    }

    init?(ianaId: String, rawUTCOffset: String) {
        let normalizedIanaId = ianaId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOffset = rawUTCOffset.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^([+-])(\d{2}):(\d{2})$"#
        guard !normalizedIanaId.isEmpty,
              let match = Self.match(pattern: pattern, in: normalizedOffset),
              let signRange = Range(match.range(at: 1), in: normalizedOffset),
              let hourRange = Range(match.range(at: 2), in: normalizedOffset),
              let minuteRange = Range(match.range(at: 3), in: normalizedOffset),
              let hours = Int(normalizedOffset[hourRange]),
              let minutes = Int(normalizedOffset[minuteRange]),
              minutes < 60 else {
            return nil
        }

        let magnitude = hours * 60 + minutes
        guard magnitude <= 14 * 60 else {
            return nil
        }

        let sign = normalizedOffset[signRange] == "-" ? -1 : 1
        self.ianaId = normalizedIanaId
        self.offsetMinutes = sign * magnitude
    }

    var displayOffset: String {
        let sign = offsetMinutes < 0 ? "-" : "+"
        let magnitude = abs(offsetMinutes)
        return String(format: "UTC%@%02d:%02d", sign, magnitude / 60, magnitude % 60)
    }

    var storageValue: String {
        return "\(ianaId) (\(displayOffset))"
    }

    var isMeshTimeZoneOffsetEncodable: Bool {
        let encodedOffset = offsetMinutes / 15 + 64
        return offsetMinutes.isMultiple(of: 15)
            && (0...Int(UInt8.max)).contains(encodedOffset)
    }

    func formattedLocalDate(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: offsetMinutes * 60)
        formatter.dateFormat = "yyyy-M-d h:mm:ss a"
        return formatter.string(from: date)
    }
}

private extension SiteTimeZoneValue {

    static func match(pattern: String, in value: String) -> NSTextCheckingResult? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.firstMatch(in: value, range: range)
    }
}
