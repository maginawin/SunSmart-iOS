//
//  NetworkRequest.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/5/28.
//

import Foundation
import Moya
import SwiftyJSON
import Alamofire
import Compression

class NetworkRequest: NSObject {
    
    typealias Success = ([String: Any]) -> Void
    typealias Failure = (NSError) -> Void
    
    public typealias Completion = (_ result: Result<[String: Any], NetworkApiError>) -> Void
    
    static let shared = NetworkRequest()
    
    private let reachabilityManager = NetworkReachabilityManager()
    
//    lazy var session: Session = {
//        let configuration = URLSessionConfiguration.default
//        configuration.timeoutIntervalForRequest = 20 // 单次请求超时
//        configuration.timeoutIntervalForResource = 60 // 整体资源超时
//        configuration.httpMaximumConnectionsPerHost = 6 // 提高连接数
//        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData // 避免缓存干扰测试
//        let session = Session(configuration: configuration)
//        return session
//    }()
    
    private static let responseQueue = DispatchQueue(label: "com.sunsmart.http-response", qos: .userInitiated)
    private static let encodingQueue = DispatchQueue(label: "com.sunsmart.http-encoding", qos: .userInitiated)

    lazy var provider = MoyaProvider<NetowrkReqeustApi>(
        requestClosure: requestClosure,
        session: Session(configuration: URLSessionConfiguration.af.default, startRequestsImmediately: false,
                         eventMonitors: [NetworkTransferMetricsMonitor()]),
        plugins: [NetworkRequestTimeoutPlugin(), NetworkLoggerPlugin()]
    )
    /// 手机是否联网
    @objc dynamic var networkable: Bool = false
    
    // MARK: - 设置请求token和超时时间
    private let requestClosure = { (endpoint: Endpoint, done: @escaping MoyaProvider.RequestResultClosure) in
        NetworkRequest.encodingQueue.async {
            do {
                var request = try endpoint.urlRequest()
                request.timeoutInterval = 10
                request = try HTTPBodyEncoding.prepare(request)
                done(.success(request))
            } catch {
                done(.failure(MoyaError.underlying(error, nil)))
            }
        }
    }
    
    /// 开始网络连接监听
    func networkListener() {
        reachabilityManager?.startListening(onUpdatePerforming: { networkStatus in
            switch networkStatus {
            case .reachable:
                if !self.networkable {
                    self.networkable = true
                }
//                break
            default:
                if self.networkable {
                    self.networkable = false
                }
            }
        })
    }
    
    @discardableResult func request(_ target: NetowrkReqeustApi) async -> Result<[String: Any], NetworkApiError> {
        return await withCheckedContinuation { continuation in
            self.request(target) { result in
                continuation.resume(returning: result)
            }
        }
    }

    @discardableResult func request(
        _ target: NetowrkReqeustApi,
        maximumDuration: TimeInterval
    ) async -> Result<[String: Any], NetworkApiError> {
        guard maximumDuration > 0 else {
            return .failure(.requestTimeout)
        }
        return await withCheckedContinuation { continuation in
            let gate = NetworkTimedRequestGate { result in
                continuation.resume(returning: result)
            }
            let timeoutWorkItem = DispatchWorkItem {
                gate.finish(with: .failure(.requestTimeout))
            }
            gate.install(timeoutWorkItem: timeoutWorkItem)
            let cancellable = self.request(target) { result in
                gate.finish(with: result)
            }
            gate.install(cancellable: cancellable)
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + maximumDuration,
                execute: timeoutWorkItem
            )
        }
    }
    
    @discardableResult func request(_ target: NetowrkReqeustApi, completion: @escaping Completion) -> Cancellable {
        
        return provider.request(target, callbackQueue: Self.responseQueue) { result in
            let deliver: Completion = { value in DispatchQueue.main.async { completion(value) } }
            let started = ProcessInfo.processInfo.systemUptime
            defer {
                #if DEBUG
                print("[HTTP][Decode] target=\(target.diagnosticName) seconds=\(ProcessInfo.processInfo.systemUptime - started) main=\(Thread.isMainThread)")
                #endif
            }
            switch result {
            case .success(let respond):
                do {
//                    if let httpResponse = respond.response as? HTTPURLResponse,
//                       httpResponse.value(forHTTPHeaderField: "Content-Encoding")?.contains("gzip") ?? false {
//                        
//                    }
                    let jsonObject = try respond.mapJSON()
                    guard let json = jsonObject as? [String: Any] else {
                        deliver(.failure(.init(
                            code: respond.statusCode,
                            message: "Expected JSON object response",
                            httpStatusCode: respond.statusCode,
                            responseBody: Self.responseBodySummary(respond.data)
                        )))
                        return
                    }
                    // 服务器返回成功
                    let businessCode = JSON(json as Any)["code"]
                    let code = businessCode.int ?? businessCode.string.flatMap(Int.init)
                    let isSuccess = JSON(json as Any)["isSuccess"].bool ?? false
                    if (200..<300).contains(respond.statusCode), code == 200 || isSuccess || json.isEmpty {
                        deliver(.success(json))
//                        success?(json!)
                    }else {
                        let responseJSON = JSON(json as Any)
                        deliver(.failure(.init(
                            code: code ?? ((200..<300).contains(respond.statusCode) ? -1 : respond.statusCode),
                            message: responseJSON["message"].string ?? responseJSON["msg"].string,
                            httpStatusCode: respond.statusCode,
                            responseBody: Self.responseBodySummary(respond.data)
                        )))
//                        if code == 4001 { // token过期
//                            userTokenExpiredDispose()
//                        }
                    }
                } catch let error {
                    let moyaResponse = (error as? MoyaError)?.response
                    let nsError = error as NSError
                    let errorCode = moyaResponse?.statusCode ?? nsError.code
                    deliver(.failure(.init(
                        code: errorCode,
                        message: error.localizedDescription,
                        httpStatusCode: moyaResponse?.statusCode,
                        responseBody: moyaResponse.map { Self.responseBodySummary($0.data) },
                        underlyingError: nsError
                    )))
                }
            case .failure(let error):
                var errorCode = (error as NSError).code
                var underlyingError = error as NSError
                switch error {
                case .underlying(let resultError, _):
                    underlyingError = resultError as NSError
                    if let requestError = (resultError as? AFError)?.underlyingError as? NSError {
                        errorCode = requestError.code
                        underlyingError = requestError
                    }
                default:
                    break
                }

                deliver(.failure(.init(
                    code: errorCode,
                    message: error.localizedDescription,
                    httpStatusCode: error.response?.statusCode,
                    responseBody: error.response.map { Self.responseBodySummary($0.data) },
                    underlyingError: underlyingError
                )))
//                switch error {
//                case .underlying(let resultError, _):
//                    let requestError = (resultError as NSError)
//                    failure?(requestError)
//                    if requestError.code == noInterNetworkCode { // 无网络提示
//                        showNoInterNetworkMessage()
//                    }else if requestError.code == networkRequestTimeoutCode { // 请求超时
//                        showNetworkTimeoutMessage()
//                    }
//                default:
//                    failure?(error as NSError)
//                }
            }
        }
        
    }
    
    
    /// 网络请求接口
    /// - Parameters:
    ///   - target: 接口数据
    ///   - success: 成功回调
    ///   - failure: 失败回调
    @discardableResult func request(_ target: NetowrkReqeustApi, success: Success?, failure: Failure?) -> Cancellable {
        
       return provider.request(target, callbackQueue: Self.responseQueue) { result in
            let success: Success? = success.map { callback in { value in DispatchQueue.main.async { callback(value) } } }
            let failure: Failure? = failure.map { callback in { value in DispatchQueue.main.async { callback(value) } } }
            switch result {
            case .success(let respond):
                do {
                    let json = try respond.filter(statusCode: 200).mapJSON() as? [String: Any]
                    // 服务器返回成功
                    let code = JSON(json as Any)["code"].intValue
                    let isSuccess = JSON(json as Any)["isSuccess"].bool ?? false
                    if code == 200 || isSuccess {
                        success?(json!)
                    }else {
                        
                        failure?(NSError(domain: json?["message"] as? String ?? "", code: code))
                        
//                        if code == 4001 { // token过期
//                            userTokenExpiredDispose()
//                        }
                    }
                } catch let error {
                    failure?(error as NSError)
                }
            case .failure(let error):
                switch error {
                case .underlying(let resultError, _):
                    let requestError = (resultError as NSError)
                    failure?(requestError)
//                    if requestError.code == noInterNetworkCode { // 无网络提示
//                        showNoInterNetworkMessage()
//                    }else if requestError.code == networkRequestTimeoutCode { // 请求超时
//                        showNetworkTimeoutMessage()
//                    }
                default:
                    failure?(error as NSError)
                }
            }
        }
                
    }
    
}

private struct NetworkRequestTimeoutPlugin: PluginType {
    func prepare(_ request: URLRequest, target: TargetType) -> URLRequest {
        guard let api = target as? NetowrkReqeustApi else {
            return request
        }
        var request = request
        request.timeoutInterval = api.requestTimeoutInterval
        return request
    }
}

private final class NetworkTimedRequestGate {
    typealias ResultType = Result<[String: Any], NetworkApiError>

    private let lock = NSLock()
    private let completion: (ResultType) -> Void
    private var cancellable: Cancellable?
    private var timeoutWorkItem: DispatchWorkItem?
    private var didFinish = false

    init(completion: @escaping (ResultType) -> Void) {
        self.completion = completion
    }

    func install(cancellable: Cancellable) {
        lock.lock()
        if didFinish {
            lock.unlock()
            cancellable.cancel()
            return
        }
        self.cancellable = cancellable
        lock.unlock()
    }

    func install(timeoutWorkItem: DispatchWorkItem) {
        lock.lock()
        if didFinish {
            lock.unlock()
            timeoutWorkItem.cancel()
            return
        }
        self.timeoutWorkItem = timeoutWorkItem
        lock.unlock()
    }

    func finish(with result: ResultType) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        let cancellable = self.cancellable
        let timeoutWorkItem = self.timeoutWorkItem
        self.cancellable = nil
        self.timeoutWorkItem = nil
        lock.unlock()

        timeoutWorkItem?.cancel()
        if case .failure(.requestTimeout) = result {
            cancellable?.cancel()
        }
        completion(result)
    }
}

private extension NetworkRequest {

    static func responseBodySummary(_ data: Data, limit: Int = 3000) -> String {
        guard !data.isEmpty else {
            return "<empty>"
        }
        let string = String(data: data, encoding: .utf8) ?? "<non-utf8 body: \(data.count) bytes>"
        guard string.count > limit else {
            return string
        }
        return "\(string.prefix(limit))... <truncated, \(string.count) chars>"
    }
}


/// 网络请求api错误
public enum NetworkApiError: Error, Equatable {

    var code: Int {
        switch self {
        case .unknown:
            return 9999
        case .apiError(let code, _, _, _, _, _):
            return code
        case .noNetwork:
            return -1009
        case .requestTimeout:
            return -1001
        case .serverNotRespond:
            return 502
        case .resourceNotFound:
            return 4004
        case .visitorBeingUsedSpace:
            return 4005
        case .editorBeingUsedSpace:
            return 4006
        case .noSitePermission:
            return 4008
        case .noSpacePermission:
            return 4009
        case .userUnauthorized:
            return 4010
        case .incorrectPassword:
            return 4011
        case .spaceAlreadyExist:
            return 4012
        case .spacePasswordOverdue:
            return 4015
        case .configurationUploadUnconfirmed:
            return -2002
        case .configurationExportInvalid:
            return -2003
        case .meshKeysUnavailable:
            return -2004
        case .meshKeyConflict:
            return -2005
        }
    }
    
    init(code: Int) {
        self.init(code: code, message: nil, httpStatusCode: nil, responseBody: nil, underlyingError: nil)
    }

    init(
        code: Int,
        message: String?,
        httpStatusCode: Int?,
        responseBody: String?,
        underlyingError: NSError? = nil
    ) {
        switch code {
        case -2002:
            self = .configurationUploadUnconfirmed
        case -2003:
            self = .configurationExportInvalid
        case -2004:
            self = .meshKeysUnavailable
        case -2005:
            self = .meshKeyConflict
        case -1009, -1020:
            self = .noNetwork
        case -1001:
            self = .requestTimeout
        case 502:
            self = .serverNotRespond
        case 4004:
            self = .resourceNotFound
        case 4005:
            self = .visitorBeingUsedSpace
        case 4006:
            self = .editorBeingUsedSpace
        case 4008:
            self = .noSitePermission
        case 4009:
            self = .noSpacePermission
        case 4010:
            self = .userUnauthorized
        case 4011:
            self = .incorrectPassword
        case 4012:
            self = .spaceAlreadyExist
        case 4015:
            self = .spacePasswordOverdue
        case 9999 where message == nil && httpStatusCode == nil && responseBody == nil && underlyingError == nil:
            self = .unknown
        default:
            self = .apiError(
                code: code,
                message: message,
                httpStatusCode: httpStatusCode,
                responseBody: responseBody,
                underlyingDomain: underlyingError?.domain,
                underlyingCode: underlyingError?.code
            )
        }
    }
    
    /// 未知错误
    case unknown
    /// Local configuration sync failures retain their localized meaning after reload.
    case configurationUploadUnconfirmed
    case configurationExportInvalid
    case meshKeysUnavailable
    case meshKeyConflict
    /// 未识别的服务器或底层错误，保留原始诊断信息
    case apiError(
        code: Int,
        message: String?,
        httpStatusCode: Int?,
        responseBody: String?,
        underlyingDomain: String?,
        underlyingCode: Int?
    )
    /// 没有网络
    case noNetwork
    /// 网络请求超时
    case requestTimeout
    /// 服务器未响应
    case serverNotRespond
    /// 找不到资源
    case resourceNotFound
    /// 访客正在使用空间
    case visitorBeingUsedSpace
    /// 编辑者/Editor正在使用空间
    case editorBeingUsedSpace
    /// 无site权限
    case noSitePermission
    /// 无space权限
    case noSpacePermission
    /// 用户未授权（未加入空间）
    case userUnauthorized
    /// space密码错误
    case incorrectPassword
    /// 空间已存在(加入已存在的空间)
    case spaceAlreadyExist
    /// 空间密码过期（被高权限用户修改密码）
    case spacePasswordOverdue
}

extension NetworkApiError: LocalizedError {
    
    public var errorDescription: String? {
        switch self {
        case .configurationUploadUnconfirmed:
            return "configuration_upload_unconfirmed".localizedString
        case .configurationExportInvalid:
            return "proximity_lighting_export_invalid".localizedString
        case .meshKeysUnavailable:
            return "space_mesh_keys_unavailable".localizedString
        case .meshKeyConflict:
            return "space_mesh_key_conflict".localizedString
        case .noNetwork:
            return "phone_no_network".localizedString
        case .requestTimeout:
            return "network_request_timeout".localizedString
        case .serverNotRespond:
            return "server_not_responding".localizedString
        case .resourceNotFound:
            return "resource_not_found".localizedString
        case .visitorBeingUsedSpace:
            return "space_visitors_are_using".localizedString
        case .editorBeingUsedSpace:
            return "space_editor_are_using".localizedString
        case .noSitePermission, .noSpacePermission, .userUnauthorized:
            return "no_permission".localizedString
        case .incorrectPassword:
            return "incorrect_password!".localizedString
        case .spaceAlreadyExist:
            return "space_already_exist".localizedString
        case .spacePasswordOverdue:
            return "space_password_overdue".localizedString
        case .unknown, .apiError:
            return "unknown_error".localizedString
        }
    }
}

extension NetworkApiError {

    /// Keep string business codes without changing the persisted error shape.
    var responseBusinessCode: String? {
        guard case .apiError(_, _, _, let body, _, _) = self,
              let data = body?.data(using: .utf8),
              let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return response["code"] as? String
    }

    /// A parser rejection occurs before configuration writes. Other 4xx/5xx
    /// and transport errors remain unknown outcomes and still need readback.
    var isRequestParseRejection: Bool {
        guard case .apiError(_, _, let status, _, let domain, let underlyingCode) = self else { return false }
        return status == 400 && responseBusinessCode == "parse_error" && domain == nil && underlyingCode == nil
    }

    var diagnosticDescription: String {
        switch self {
        case .apiError(let code, let message, let httpStatusCode, let responseBody, let underlyingDomain, let underlyingCode):
            return "code=\(code), businessCode=\(responseBusinessCode ?? "<missing>"), message=\(message ?? "<missing>"), httpStatus=\(httpStatusCode?.description ?? "<missing>"), underlyingDomain=\(underlyingDomain ?? "<missing>"), underlyingCode=\(underlyingCode?.description ?? "<missing>"), responseBody=\(responseBody ?? "<missing>")"
        default:
            return "code=\(code), localizedDescription=\(localizedDescription)"
        }
    }
}

/// Encoding is selected from the final URLRequest; headers always describe actual bytes.
enum HTTPBodyEncoding {
    static func prepare(_ original: URLRequest) throws -> URLRequest {
        var request = original
        request.setValue(nil, forHTTPHeaderField: "Content-Encoding")
        let path = request.url?.path ?? ""
        let isUpload = path.hasSuffix("/sitespace/sync/siteprops") || path.hasSuffix("/sitespace/sync/spaceprops")
        if isUpload {
            request.setValue(nil, forHTTPHeaderField: "Content-Length")
        }
        // Both sync endpoints support request compression in all server regions.
        // Accept-Encoding negotiates responses independently of this policy.
        guard isUpload,
              request.httpMethod == "POST",
              let body = request.httpBody, !body.isEmpty else { return request }
        request.httpBody = body.isGzipped ? body : try body.gzipped(level: .bestSpeed)
        request.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
        return request
    }
}

private final class NetworkTransferMetricsMonitor: EventMonitor {
    let queue = DispatchQueue(label: "com.sunsmart.http-metrics")
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        #if DEBUG
        for metric in metrics.transactionMetrics {
            let response = metric.response as? HTTPURLResponse
            print("[HTTP][Metrics] task=\(task.taskIdentifier) path=\(metric.request.url?.path ?? "") encoding=\(response?.value(forHTTPHeaderField: "Content-Encoding") ?? "identity") receivedBytes=\(metric.countOfResponseBodyBytesReceived) decodedBytes=\(metric.countOfResponseBodyBytesAfterDecoding)")
        }
        #endif
    }
}
