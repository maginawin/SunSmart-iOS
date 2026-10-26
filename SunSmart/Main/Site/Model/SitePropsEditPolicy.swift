import Foundation

/// Standard Site properties shared by creation, full sync and partial props reads.
struct SiteStandardProperties: Equatable {
    var latitude: Double?
    var longitude: Double?
    var countryRegion: String?
    var postalCode: String?
    var city: String?
    var address: String?
    var siteDescription: String?

    static let keys = ["latitude", "longitude", "countryRegion", "postalCode", "city", "address", "description"]
    private static let textFields: [(String, WritableKeyPath<Self, String?>)] = [
        ("countryRegion", \.countryRegion), ("postalCode", \.postalCode),
        ("city", \.city), ("address", \.address), ("description", \.siteDescription)
    ]

    var isValid: Bool {
        (latitude.map { $0.isFinite && (-90...90).contains($0) } ?? true)
            && (longitude.map { $0.isFinite && (-180...180).contains($0) } ?? true)
    }

    var jsonObject: [String: Any] {
        var result: [String: Any] = ["latitude": latitude as Any? ?? NSNull(),
                                     "longitude": longitude as Any? ?? NSNull()]
        for (key, path) in Self.textFields { result[key] = self[keyPath: path] as Any? ?? NSNull() }
        return result
    }

    /// Presence is separate from value: omitted fields preserve, explicit null clears.
    struct Patch: Equatable {
        enum ParseError: Error { case invalidField(String) }
        private var values = SiteStandardProperties()
        private var provided: Set<String> = []

        init() {}

        init(_ object: [String: Any]) throws {
            for (key, path) in SiteStandardProperties.textFields {
                guard let raw = object[key] else { continue }
                provided.insert(key)
                if raw is NSNull { continue }
                guard let text = raw as? String else { throw ParseError.invalidField(key) }
                values[keyPath: path] = text
            }
            for key in ["latitude", "longitude"] {
                guard let raw = object[key] else { continue }
                provided.insert(key)
                if raw is NSNull { continue }
                let value: Double
                if let number = raw as? NSNumber,
                   CFGetTypeID(number) != CFBooleanGetTypeID() {
                    value = number.doubleValue
                } else if let text = raw as? String,
                          let number = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    // Legacy Site responses encode coordinates as numeric strings.
                    value = number
                } else {
                    throw ParseError.invalidField(key)
                }
                let range: ClosedRange<Double> = key == "latitude" ? -90...90 : -180...180
                guard value.isFinite, range.contains(value) else { throw ParseError.invalidField(key) }
                if key == "latitude" { values.latitude = value } else { values.longitude = value }
            }
        }

        func applying(to current: SiteStandardProperties) -> SiteStandardProperties {
            var result = current
            for (key, path) in SiteStandardProperties.textFields where provided.contains(key) {
                result[keyPath: path] = values[keyPath: path]
            }
            if provided.contains("latitude") { result.latitude = values.latitude }
            if provided.contains("longitude") { result.longitude = values.longitude }
            return result
        }

        func merging(to current: SiteStandardProperties, localTimestamp: Int64,
                     remoteTimestamp: Int64, hasPendingChanges: Bool) -> SiteStandardProperties {
            guard remoteTimestamp >= localTimestamp, !hasPendingChanges else { return current }
            return applying(to: current)
        }
    }
}

struct SitePropsFieldMask: OptionSet, Equatable {
    let rawValue: Int

    static let siteName = SitePropsFieldMask(rawValue: 1 << 0)
    static let imageId = SitePropsFieldMask(rawValue: 1 << 1)
    static let timezone = SitePropsFieldMask(rawValue: 1 << 2)
}

struct SitePropsValues: Equatable {
    var siteName: String
    var imageId: Int
    var timezone: SiteTimeZoneValue?
}

struct SitePropsPendingState: Equatable {
    let fields: SitePropsFieldMask
    let timestamp: Int64?
}

struct SitePropsLocalState: Equatable {
    let values: SitePropsValues
    let lastUpdate: Int64
    let lastUploadCloudTimestamp: Int64?
    let pending: SitePropsPendingState
    var standardProperties = SiteStandardProperties()
}

struct SitePropsRemoteSnapshot: Equatable {
    let siteName: String?
    let imageId: Int?
    let timezone: SiteTimeZoneValue?
    let providedFields: SitePropsFieldMask
    let timestamp: Int64
    var standardProperties = SiteStandardProperties.Patch()
}

struct SitePropsUpdateSnapshot: Equatable {
    let siteId: String
    let fields: SitePropsFieldMask
    let values: SitePropsValues
    let timestamp: Int64
}

struct SiteInitialTimeZoneSubmission: Equatable {
    let timezone: SiteTimeZoneValue
    let timestamp: Int64
}

struct SitePropsRetrieveMergeResult: Equatable {
    let state: SitePropsLocalState
    let shouldPersist: Bool
}

enum SitePropsEditPolicy {

    static func changedFields(
        from original: SitePropsValues,
        to draft: SitePropsValues
    ) -> SitePropsFieldMask {
        var fields: SitePropsFieldMask = []
        if original.siteName != draft.siteName {
            fields.insert(.siteName)
        }
        if original.imageId != draft.imageId {
            fields.insert(.imageId)
        }
        if original.timezone != draft.timezone {
            fields.insert(.timezone)
        }
        return fields
    }

    static func nextTimestamp(now: Int64, current: Int64) -> Int64 {
        return now > current ? now : current + 1
    }

    static func makeUpdateSnapshot(
        siteId: String,
        local: SitePropsLocalState,
        original: SitePropsValues,
        draft: SitePropsValues,
        now: Int64
    ) -> SitePropsUpdateSnapshot? {
        let changed = changedFields(from: original, to: draft)
        let fields = local.pending.fields.union(changed)
        guard !fields.isEmpty else { return nil }

        let timestamp: Int64
        if changed.isEmpty, let pendingTimestamp = local.pending.timestamp {
            timestamp = pendingTimestamp
        } else {
            timestamp = nextTimestamp(now: now, current: local.lastUpdate)
        }

        return SitePropsUpdateSnapshot(
            siteId: siteId,
            fields: fields,
            values: draft,
            timestamp: timestamp
        )
    }

    static func mergeRetrieve(
        local: SitePropsLocalState,
        remote: SitePropsRemoteSnapshot
    ) -> SitePropsRetrieveMergeResult {
        var mergeBase = local

        if !local.pending.fields.isEmpty {
            guard
                let pendingTimestamp = local.pending.timestamp,
                remote.timestamp >= pendingTimestamp,
                remoteMatchesLocalPending(remote: remote, local: local)
            else {
                return SitePropsRetrieveMergeResult(state: local, shouldPersist: false)
            }

            mergeBase = SitePropsLocalState(
                values: local.values,
                lastUpdate: local.lastUpdate,
                lastUploadCloudTimestamp: local.lastUploadCloudTimestamp,
                pending: SitePropsPendingState(fields: [], timestamp: nil),
                standardProperties: local.standardProperties
            )
        }

        guard remote.timestamp >= mergeBase.lastUpdate else {
            return SitePropsRetrieveMergeResult(
                state: mergeBase,
                shouldPersist: mergeBase != local
            )
        }

        var siteName = mergeBase.values.siteName
        var imageId = mergeBase.values.imageId
        var timezone = mergeBase.values.timezone

        if remote.providedFields.contains(.siteName), let remoteSiteName = remote.siteName {
            siteName = remoteSiteName
        }
        if remote.providedFields.contains(.imageId), let remoteImageId = remote.imageId {
            imageId = remoteImageId
        }
        if remote.providedFields.contains(.timezone), let remoteTimezone = remote.timezone {
            timezone = remoteTimezone
        }

        let merged = SitePropsLocalState(
            values: SitePropsValues(
                siteName: siteName,
                imageId: imageId,
                timezone: timezone
            ),
            lastUpdate: remote.timestamp,
            lastUploadCloudTimestamp: remote.timestamp,
            pending: mergeBase.pending,
            standardProperties: remote.standardProperties.applying(to: mergeBase.standardProperties)
        )
        return SitePropsRetrieveMergeResult(
            state: merged,
            shouldPersist: merged != local
        )
    }

    static func updateResponseMatches(
        request: SitePropsUpdateSnapshot,
        response: SitePropsRemoteSnapshot
    ) -> Bool {
        guard response.timestamp == request.timestamp else { return false }

        if request.fields.contains(.siteName) {
            guard
                response.providedFields.contains(.siteName),
                response.siteName == request.values.siteName
            else { return false }
        }
        if request.fields.contains(.imageId) {
            guard
                response.providedFields.contains(.imageId),
                response.imageId == request.values.imageId
            else { return false }
        }
        if request.fields.contains(.timezone) {
            guard
                response.providedFields.contains(.timezone),
                response.timezone == request.values.timezone
            else { return false }
        }
        return true
    }

    static func localStateAfterSuccessfulUpdate(
        current: SitePropsLocalState,
        request: SitePropsUpdateSnapshot
    ) -> SitePropsLocalState {
        guard
            current.pending.timestamp == request.timestamp,
            localValuesMatchRequest(current.values, request: request)
        else { return current }

        let remainingFields = current.pending.fields.subtracting(request.fields)
        return SitePropsLocalState(
            values: current.values,
            lastUpdate: current.lastUpdate,
            lastUploadCloudTimestamp: request.timestamp,
            pending: SitePropsPendingState(
                fields: remainingFields,
                timestamp: remainingFields.isEmpty ? nil : current.pending.timestamp
            ),
            standardProperties: current.standardProperties
        )
    }

    static func localStateAfterSuccessfulInitialSiteUpload(
        current: SitePropsLocalState,
        submission: SiteInitialTimeZoneSubmission
    ) -> SitePropsLocalState {
        var remainingFields = current.pending.fields
        if remainingFields.contains(.timezone),
           current.pending.timestamp == submission.timestamp,
           current.values.timezone == submission.timezone {
            remainingFields.remove(.timezone)
        }

        let confirmedTimestamp = max(
            current.lastUploadCloudTimestamp ?? submission.timestamp,
            submission.timestamp
        )
        return SitePropsLocalState(
            values: current.values,
            lastUpdate: current.lastUpdate,
            lastUploadCloudTimestamp: confirmedTimestamp,
            pending: SitePropsPendingState(
                fields: remainingFields,
                timestamp: remainingFields.isEmpty ? nil : current.pending.timestamp
            ),
            standardProperties: current.standardProperties
        )
    }

    private static func remoteMatchesLocalPending(
        remote: SitePropsRemoteSnapshot,
        local: SitePropsLocalState
    ) -> Bool {
        let fields = local.pending.fields
        if fields.contains(.siteName) {
            guard
                remote.providedFields.contains(.siteName),
                remote.siteName == local.values.siteName
            else { return false }
        }
        if fields.contains(.imageId) {
            guard
                remote.providedFields.contains(.imageId),
                remote.imageId == local.values.imageId
            else { return false }
        }
        if fields.contains(.timezone) {
            guard
                remote.providedFields.contains(.timezone),
                remote.timezone == local.values.timezone
            else { return false }
        }
        return true
    }

    private static func localValuesMatchRequest(
        _ values: SitePropsValues,
        request: SitePropsUpdateSnapshot
    ) -> Bool {
        if request.fields.contains(.siteName), values.siteName != request.values.siteName {
            return false
        }
        if request.fields.contains(.imageId), values.imageId != request.values.imageId {
            return false
        }
        if request.fields.contains(.timezone), values.timezone != request.values.timezone {
            return false
        }
        return true
    }
}
