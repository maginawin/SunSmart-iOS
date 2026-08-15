//
//  SitePropsAPIClient.swift
//  SunSmart
//
//  Created by One on 2026/8/11.
//

import Foundation

protocol SitePropsAPIClientProtocol {
    func retrieve(siteId: String) async -> Result<SitePropsRemoteSnapshot, NetworkApiError>
    func update(snapshot: SitePropsUpdateSnapshot) async -> Result<SitePropsRemoteSnapshot, NetworkApiError>
}

final class SitePropsAPIClient: SitePropsAPIClientProtocol {

    private let networkRequest: NetworkRequest

    init(networkRequest: NetworkRequest = .shared) {
        self.networkRequest = networkRequest
    }

    func retrieve(siteId: String) async -> Result<SitePropsRemoteSnapshot, NetworkApiError> {
        let result = await networkRequest.request(.sitePropsRetrieve(siteId: siteId))
        switch result {
        case .success(let response):
            guard
                let data = response["data"] as? [String: Any],
                let props = data["props"] as? [String: Any],
                let siteName = props["siteName"] as? String,
                let imageId = intValue(props["imageId"]),
                let timestamp = int64Value(props["updateTimestamp"]),
                let timezoneResult = timezoneValue(in: props)
            else {
                return .failure(.unknown)
            }

            var providedFields: SitePropsFieldMask = [.siteName, .imageId]
            if timezoneResult.wasProvided {
                providedFields.insert(.timezone)
            }
            return .success(SitePropsRemoteSnapshot(
                siteName: siteName,
                imageId: imageId,
                timezone: timezoneResult.value,
                providedFields: providedFields,
                timestamp: timestamp
            ))

        case .failure(let error):
            return .failure(error)
        }
    }

    func update(snapshot: SitePropsUpdateSnapshot) async -> Result<SitePropsRemoteSnapshot, NetworkApiError> {
        var props: [String: Any] = ["updateTimestamp": snapshot.timestamp]
        if snapshot.fields.contains(.siteName) {
            props["siteName"] = snapshot.values.siteName
        }
        if snapshot.fields.contains(.imageId) {
            props["imageId"] = snapshot.values.imageId
        }
        if snapshot.fields.contains(.timezone) {
            guard let timezone = snapshot.values.timezone else {
                return .failure(.unknown)
            }
            props["timezone"] = timezone.storageValue
        }

        let result = await networkRequest.request(
            .sitePropsUpdate(siteId: snapshot.siteId, props: props)
        )
        switch result {
        case .success(let response):
            guard
                let data = response["data"] as? [String: Any],
                let parsed = parseUpdateResponse(data)
            else {
                return .failure(.unknown)
            }
            return .success(parsed)

        case .failure(let error):
            return .failure(error)
        }
    }

    func parseUpdateResponse(_ data: [String: Any]) -> SitePropsRemoteSnapshot? {
        guard let timestamp = int64Value(data["updateTimestamp"]),
              let timezoneResult = timezoneValue(in: data) else {
            return nil
        }

        var providedFields: SitePropsFieldMask = []
        var siteName: String?
        var imageId: Int?

        if data.keys.contains("siteName") {
            guard let value = data["siteName"] as? String else { return nil }
            siteName = value
            providedFields.insert(.siteName)
        }
        if data.keys.contains("imageId") {
            guard let value = intValue(data["imageId"]) else { return nil }
            imageId = value
            providedFields.insert(.imageId)
        }
        if timezoneResult.wasProvided {
            providedFields.insert(.timezone)
        }

        return SitePropsRemoteSnapshot(
            siteName: siteName,
            imageId: imageId,
            timezone: timezoneResult.value,
            providedFields: providedFields,
            timestamp: timestamp
        )
    }

    private func timezoneValue(
        in props: [String: Any]
    ) -> (value: SiteTimeZoneValue?, wasProvided: Bool)? {
        guard props.keys.contains("timezone") else {
            return (nil, false)
        }
        let rawValue = props["timezone"]
        if rawValue is NSNull {
            return (nil, false)
        }
        guard let timezoneString = rawValue as? String else {
            return nil
        }
        guard !timezoneString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (nil, false)
        }
        guard let timezone = SiteTimeZoneValue(storageValue: timezoneString) else {
            return nil
        }
        return (timezone, true)
    }

    private func isBoolean(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private func intValue(_ value: Any?) -> Int? {
        guard let value, !isBoolean(value) else { return nil }
        if let integer = value as? Int {
            return integer
        }
        guard let number = value as? NSNumber else { return nil }
        let double = number.doubleValue
        guard double.isFinite,
              double.rounded(.towardZero) == double,
              double >= Double(Int.min),
              double <= Double(Int.max) else {
            return nil
        }
        return Int(double)
    }

    private func int64Value(_ value: Any?) -> Int64? {
        guard let value, !isBoolean(value) else { return nil }
        if let integer = value as? Int64 {
            return integer
        }
        guard let number = value as? NSNumber else { return nil }
        let double = number.doubleValue
        guard double.isFinite,
              double.rounded(.towardZero) == double,
              double >= Double(Int64.min),
              double <= Double(Int64.max) else {
            return nil
        }
        return Int64(double)
    }
}
