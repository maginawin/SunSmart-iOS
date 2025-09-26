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
    
    lazy var provider = MoyaProvider<NetowrkReqeustApi>(requestClosure: requestClosure, plugins: [NetworkLoggerPlugin()])
    /// 手机是否联网
    @objc dynamic var networkable: Bool = false
    
    // MARK: - 设置请求token和超时时间
    private let requestClosure = { (endpoint: Endpoint, done: @escaping MoyaProvider.RequestResultClosure) in
        do {
            var request = try endpoint.urlRequest()
            request.timeoutInterval = 10    //设置请求超时时间
            // 判断请求体数据过大压缩
//            if let body = request.httpBody, body.count > 1024 * 100 {
//                let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: body.count)
//                let compressedSize = compression_encode_buffer(destinationBuffer, body.count, [UInt8](body), body.count, nil, COMPRESSION_ZLIB)
//                if compressedSize > 0 {
//                    request.httpBody = Data(bytes: destinationBuffer, count: compressedSize)
//                }
//            }
        
                done(.success(request))
//            }
        } catch {
            done(.failure(MoyaError.underlying(error, nil)))
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
    
    @discardableResult func request(_ target: NetowrkReqeustApi, completion: @escaping Completion) -> Cancellable {
        
        return provider.request(target) { result in
            switch result {
            case .success(let respond):
                do {
//                    if let httpResponse = respond.response as? HTTPURLResponse,
//                       httpResponse.value(forHTTPHeaderField: "Content-Encoding")?.contains("gzip") ?? false {
//                        
//                    }
                    let json = try respond.mapJSON() as? [String: Any]
                    // 服务器返回成功
                    let code = JSON(json as Any)["code"].intValue
                    let isSuccess = JSON(json as Any)["isSuccess"].bool ?? false
                    if code == 200 || isSuccess || (json != nil && json!.isEmpty) {
                        completion(.success(json!))
//                        success?(json!)
                    }else {
                        
                        completion(.failure(.init(code: code)))
//                        if code == 4001 { // token过期
//                            userTokenExpiredDispose()
//                        }
                    }
                } catch let error {
                    let errorCode = (error as? MoyaError)?.response?.statusCode ?? (error as NSError).code
                    completion(.failure(.init(code: errorCode)))
                }
            case .failure(let error):
                
                var errorCode = (error as NSError).code
                switch error {
                case .underlying(let resultError, _):
                    if let requestError = (resultError as? AFError)?.underlyingError as? NSError {
                        errorCode = requestError.code
                    }
                default:
                    break
                }
                
                completion(.failure(.init(code: errorCode)))
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
        
       return provider.request(target) { result in
            
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


/// 网络请求api错误
public enum NetworkApiError: Error {
    
    var code: Int {
        switch self {
        case .unknown:
            return 9999
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
        }
    }
    
    init(code: Int) {
        switch code {
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
        default:
            self = .unknown
        }
    }
    
    /// 未知错误
    case unknown
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
        case .unknown:
            return "unknown_error".localizedString
        }
    }
}
