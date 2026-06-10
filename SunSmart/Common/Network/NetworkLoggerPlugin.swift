//
//  NetworkLoggerPlugin.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/6/13.
//

import Foundation
import Moya
import SwiftyJSON
import Alamofire

final class NetworkLoggerPlugin: PluginType {

    private let bodySummaryLimit = 3000

    // Called immediately before a request is sent over the network (or stubbed).
    func willSend(_ request: RequestType, target: TargetType) {
        #if DEBUG
        guard let networkTarget = target as? NetowrkReqeustApi else {
            print("[HTTP][Request] target=\(String(describing: target)) url=\(request.request?.url?.absoluteString ?? "<unknown>")")
            return
        }

        let urlRequest = request.request
        print("""
        [HTTP][Request]
        target=\(networkTarget.diagnosticName)
        method=\(urlRequest?.httpMethod ?? networkTarget.method.rawValue)
        url=\(urlRequest?.url?.absoluteString ?? networkTarget.baseURL.appendingPathComponent(networkTarget.path).absoluteString)
        path=\(networkTarget.path)
        headers=\(urlRequest?.allHTTPHeaderFields ?? [:])
        bodyBytes=\(urlRequest?.httpBody?.count ?? 0)
        declaredContentEncodingGzip=\(networkTarget.declaredContentEncodingGzip)
        actualBodyGzip=\(networkTarget.actualBodyGzip)
        body=\(requestBodySummary(urlRequest: urlRequest, target: networkTarget))
        """)
        printDeviceParameterUploadNodeProbeIfNeeded(target: networkTarget)
        #endif
    }

    // Called after a response has been received, but before the completion handler is called.
    func didReceive(_ result: Result<Response, MoyaError>, target: TargetType) {
        #if DEBUG
        let networkTarget = target as? NetowrkReqeustApi
        switch result {
        case .success(let response):
            let responseJSON = try? JSON(data: response.data)
            let businessCode = responseJSON?["code"].int
            let businessMessage = responseJSON?["message"].string ?? responseJSON?["msg"].string
            print("""
            [HTTP][Response]
            target=\(networkTarget?.diagnosticName ?? String(describing: target))
            url=\(response.request?.url?.absoluteString ?? "<unknown>")
            status=\(response.statusCode)
            businessCode=\(businessCode.map(String.init) ?? "<missing>")
            businessMessage=\(businessMessage ?? "<missing>")
            responseBytes=\(response.data.count)
            body=\(responseBodySummary(response.data))
            """)
            printDeviceParameterNodeProbeIfNeeded(data: response.data, targetName: networkTarget?.diagnosticName)
        case .failure(let error):
            let nsError = error as NSError
            let underlying = underlyingError(from: error)
            print("""
            [HTTP][Failure]
            target=\(networkTarget?.diagnosticName ?? String(describing: target))
            url=\(error.response?.request?.url?.absoluteString ?? "<unknown>")
            status=\(error.response?.statusCode.description ?? "<missing>")
            moyaError=\(error.localizedDescription)
            nsErrorDomain=\(nsError.domain)
            nsErrorCode=\(nsError.code)
            underlyingDomain=\(underlying?.domain ?? "<missing>")
            underlyingCode=\(underlying?.code.description ?? "<missing>")
            responseBody=\(error.response.map { responseBodySummary($0.data) } ?? "<missing>")
            """)
        }
        #endif
    }
}

#if DEBUG
private extension NetworkLoggerPlugin {

    func requestBodySummary(urlRequest: URLRequest?, target: NetowrkReqeustApi) -> String {
        if let parameters = target.sanitizedParameters {
            return summary(jsonString(from: parameters))
        }
        guard let body = urlRequest?.httpBody, !body.isEmpty else {
            return "<empty>"
        }
        if body.isGzipData {
            return "<gzip body: \(body.count) bytes>"
        }
        return summary(String(data: body, encoding: .utf8) ?? "<non-utf8 body: \(body.count) bytes>")
    }

    func responseBodySummary(_ data: Data) -> String {
        guard !data.isEmpty else {
            return "<empty>"
        }
        if let json = try? JSONSerialization.jsonObject(with: data),
           JSONSerialization.isValidJSONObject(json),
           let jsonData = try? JSONSerialization.data(withJSONObject: NetowrkReqeustApi.sanitizedValue(json), options: [.sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return summary(jsonString)
        }
        return summary(String(data: data, encoding: .utf8) ?? "<non-utf8 body: \(data.count) bytes>")
    }

    func jsonString(from value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return string
    }

    func summary(_ string: String) -> String {
        guard string.count > bodySummaryLimit else {
            return string
        }
        return "\(string.prefix(bodySummaryLimit))... <truncated, \(string.count) chars>"
    }

    func printDeviceParameterNodeProbeIfNeeded(data: Data, targetName: String?) {
        guard targetName == "siteInfo" || targetName == "spaceInfo",
              let json = try? JSON(data: data) else {
            return
        }
        let nodeProbes = deviceParameterNodeProbes(in: json)
        guard nodeProbes.count > 0 else {
            print("""
            [HTTP][DeviceParameterNodeProbe]
            target=\(targetName ?? "<unknown>")
            nodeCount=0
            """)
            return
        }
        let nodeLines = nodeProbes.map { probe in
            """
            - path=\(probe.path), uuid=\(probe.uuid), unicastAddress=\(probe.unicastAddress), cid=\(probe.cid), pid=\(probe.pid), changeControlPage=\(probe.changeControlPage), absoluteCctRangeMin=\(probe.absoluteCctRangeMin), absoluteCctRangeMax=\(probe.absoluteCctRangeMax)
            """
        }.joined(separator: "\n")
        print("""
        [HTTP][DeviceParameterNodeProbe]
        target=\(targetName ?? "<unknown>")
        nodeCount=\(nodeProbes.count)
        nodes:
        \(nodeLines)
        """)
    }

    func printDeviceParameterUploadNodeProbeIfNeeded(target: NetowrkReqeustApi) {
        let targetName = target.diagnosticName
        guard targetName == "siteAdd" || targetName == "siteUpload" || targetName == "spaceUpload",
              let parameters = target.sanitizedParameters else {
            return
        }

        let nodeProbes = deviceParameterUploadNodeProbes(in: JSON(parameters), targetName: targetName)
        guard nodeProbes.count > 0 else {
            print("""
            [HTTP][DeviceParameterUploadNodeProbe]
            target=\(targetName)
            nodeCount=0
            """)
            return
        }

        let nodeLines = nodeProbes.map { probe in
            """
            - path=\(probe.path), uuid=\(probe.uuid), unicastAddress=\(probe.unicastAddress), cid=\(probe.cid), pid=\(probe.pid), changeControlPage=\(probe.changeControlPage), absoluteCctRangeMin=\(probe.absoluteCctRangeMin), absoluteCctRangeMax=\(probe.absoluteCctRangeMax)
            """
        }.joined(separator: "\n")
        print("""
        [HTTP][DeviceParameterUploadNodeProbe]
        target=\(targetName)
        nodeCount=\(nodeProbes.count)
        nodes:
        \(nodeLines)
        """)
    }

    func deviceParameterNodeProbes(in json: JSON) -> [DeviceParameterNodeProbe] {
        var probes: [DeviceParameterNodeProbe] = []
        appendNodeProbes(from: json["data"]["nodes"], basePath: "data.nodes", into: &probes)

        for (spaceIndex, spaceJSON) in json["data"]["spaces"].arrayValue.enumerated() {
            appendNodeProbes(from: spaceJSON["nodes"], basePath: "data.spaces[\(spaceIndex)].nodes", into: &probes)
        }
        return probes
    }

    func deviceParameterUploadNodeProbes(in json: JSON, targetName: String) -> [DeviceParameterNodeProbe] {
        var probes: [DeviceParameterNodeProbe] = []
        switch targetName {
        case "siteAdd", "siteUpload":
            appendNodeProbes(from: json["site"]["nodes"], basePath: "site.nodes", into: &probes)
            for (spaceIndex, spaceJSON) in json["site"]["spaces"].arrayValue.enumerated() {
                appendNodeProbes(from: spaceJSON["nodes"], basePath: "site.spaces[\(spaceIndex)].nodes", into: &probes)
            }
        case "spaceUpload":
            for (spaceIndex, spaceJSON) in json["spaces"].arrayValue.enumerated() {
                appendNodeProbes(from: spaceJSON["nodes"], basePath: "spaces[\(spaceIndex)].nodes", into: &probes)
            }
        default:
            break
        }
        return probes
    }

    func appendNodeProbes(from nodesJSON: JSON, basePath: String, into probes: inout [DeviceParameterNodeProbe]) {
        for (nodeIndex, nodeJSON) in nodesJSON.arrayValue.enumerated() {
            probes.append(DeviceParameterNodeProbe(path: "\(basePath)[\(nodeIndex)]", json: nodeJSON))
        }
    }

    func underlyingError(from error: MoyaError) -> NSError? {
        switch error {
        case .underlying(let underlyingError, _):
            if let afError = underlyingError as? AFError,
               let requestError = afError.underlyingError as NSError? {
                return requestError
            }
            return underlyingError as NSError
        default:
            return nil
        }
    }
}

private struct DeviceParameterNodeProbe {

    let path: String
    let uuid: String
    let unicastAddress: String
    let cid: String
    let pid: String
    let changeControlPage: String
    let absoluteCctRangeMin: String
    let absoluteCctRangeMax: String

    init(path: String, json: JSON) {
        self.path = path
        self.uuid = json["uuid"].string ?? json["UUID"].string ?? "<missing>"
        self.unicastAddress = json["unicastAddress"].string ?? json["primaryUnicastAddress"].string ?? json["address"].string ?? "<missing>"
        self.cid = json["cid"].string ?? "<missing>"
        self.pid = json["pid"].string ?? json["productIdentifier"].string ?? json["productId"].string ?? "<missing>"
        self.changeControlPage = json["changeControlPage"].string ?? "<missing>"
        self.absoluteCctRangeMin = DeviceParameterNodeProbe.stringValue(json["absoluteCctRangeMin"])
        self.absoluteCctRangeMax = DeviceParameterNodeProbe.stringValue(json["absoluteCctRangeMax"])
    }

    static func stringValue(_ json: JSON) -> String {
        if let string = json.string {
            return string
        }
        if let int = json.int {
            return String(int)
        }
        if let uInt = json.uInt {
            return String(uInt)
        }
        return "<missing>"
    }
}

private extension Data {

    var isGzipData: Bool {
        count >= 2 && self[startIndex] == 0x1f && self[index(after: startIndex)] == 0x8b
    }
}
#endif
