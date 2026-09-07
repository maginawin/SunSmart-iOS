//
//  WiFiFirmwareDFUMetadataBuilder.swift
//  SunSmart
//
//  Created by Codex on 2026/7/15.
//

import Foundation

enum WiFiFirmwareDFUMetadataBuilderError: Error, Equatable {
    case invalidRegionURL
    case invalidDownloadURL
    case invalidFirmwareID
}

enum GatewayFirmwareDFUDownloadLocation: Equatable {
    case serverResponse(String)
    case regionalFilename(String)
}

struct WiFiFirmwareDFUMetadataBuilder {
    static let downloadPath = "/sitespace/ota/download"

    static func makeURL(
        filename: String,
        baseURL: URL = UserData.currentServerRegion.baseURL
    ) throws -> String {
        guard !filename.isEmpty,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw WiFiFirmwareDFUMetadataBuilderError.invalidRegionURL
        }
        components.scheme = "http"
        let basePath = components.path.hasSuffix("/")
            ? String(components.path.dropLast())
            : components.path
        components.path = basePath + downloadPath
        components.queryItems = [URLQueryItem(name: "key", value: filename)]
        guard let value = components.url?.absoluteString else {
            throw WiFiFirmwareDFUMetadataBuilderError.invalidDownloadURL
        }
        return value
    }

    static func makeURL(
        location: GatewayFirmwareDFUDownloadLocation,
        baseURL: URL = UserData.currentServerRegion.baseURL
    ) throws -> String {
        switch location {
        case .serverResponse(let url):
            guard !url.isEmpty else {
                throw WiFiFirmwareDFUMetadataBuilderError.invalidDownloadURL
            }
            return url
        case .regionalFilename(let filename):
            return try makeURL(filename: filename, baseURL: baseURL)
        }
    }

    static func firmwareID(version: String) throws -> String {
        let value = version.first == "v" || version.first == "V"
            ? String(version.dropFirst())
            : version
        guard !value.isEmpty else {
            throw WiFiFirmwareDFUMetadataBuilderError.invalidFirmwareID
        }
        return value
    }
}
