//
//  SiteGatewayCloudTimeZoneAPIClient.swift
//  SunSmart
//
//  Created by One on 2026/8/15.
//

import Foundation

enum SiteGatewayCloudTimeZoneAPIClientError: Error {
    case invalidRequestID
    case invalidStatusResponse
}

struct SiteGatewayCloudTimeZoneAPIClient: SiteGatewayCloudTimeZoneAPI {

    private let networkRequest: NetworkRequest

    init(networkRequest: NetworkRequest = .shared) {
        self.networkRequest = networkRequest
    }

    func submit(siteID: String, gatewayMACs: [String]) async throws -> Int64 {
        let result = await networkRequest.request(
            .gatewayDateTimeUpdate(siteId: siteID, gateways: gatewayMACs)
        )
        switch result {
        case .success(let response):
            guard let requestID = SiteGatewayCloudTimeZoneResponseParser.parseRequestID(from: response) else {
                throw SiteGatewayCloudTimeZoneAPIClientError.invalidRequestID
            }
            return requestID
        case .failure(let error):
            throw error
        }
    }

    func statuses(
        requestID: Int64
    ) async throws -> [SiteGatewayCloudTimeZoneRemoteStatusSnapshot] {
        guard requestID > 0 else {
            throw SiteGatewayCloudTimeZoneAPIClientError.invalidRequestID
        }
        let result = await networkRequest.request(
            .gatewayDateTimeRequestStatus(requestId: requestID)
        )
        switch result {
        case .success(let response):
            guard let statuses = SiteGatewayCloudTimeZoneResponseParser.parseStatuses(from: response) else {
                throw SiteGatewayCloudTimeZoneAPIClientError.invalidStatusResponse
            }
            return statuses
        case .failure(let error):
            throw error
        }
    }
}
