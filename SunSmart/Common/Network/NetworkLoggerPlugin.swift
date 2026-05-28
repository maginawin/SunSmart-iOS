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

private extension Data {

    var isGzipData: Bool {
        count >= 2 && self[startIndex] == 0x1f && self[index(after: startIndex)] == 0x8b
    }
}
#endif
