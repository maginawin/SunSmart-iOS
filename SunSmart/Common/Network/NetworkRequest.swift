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

class NetworkRequest: NSObject {
    
    typealias Success = ([String: Any]) -> Void
    typealias Failure = (NSError) -> Void
    
    public typealias Completion = (_ result: Result<[String: Any], NetworkApiError>) -> Void
    
    static let shared = NetworkRequest()
    
    private let reachabilityManager = NetworkReachabilityManager()
    
    lazy var provider = MoyaProvider<NetowrkReqeustApi>(requestClosure: requestClosure, plugins: [NetworkLoggerPlugin()])
    /// 手机是否联网
    @objc dynamic var networkable: Bool = false
    
    // MARK: - 设置请求token和超时时间
    private let requestClosure = { (endpoint: Endpoint, done: @escaping MoyaProvider.RequestResultClosure) in
        do {
            var request = try endpoint.urlRequest()
            request.timeoutInterval = 10    //设置请求超时时间
//            if endpoint.httpHeaderFields == nil || !endpoint.httpHeaderFields!.keys.contains(where: { $0 == "Authorization" }) {
//                // 实时获取token
//                AWSMobileClient.default().getTokens { tokens, error in
//                    DispatchQueue.main.async {
//                        if let token = tokens?.idToken?.tokenString {
//                            request.setValue(token, forHTTPHeaderField: "Authorization")
//                            request.setValue(getIdentityId(), forHTTPHeaderField: "IdentityId")
//                            done(.success(request))
//                        }else {
//                            done(.failure(MoyaError.underlying(error ?? NSError(domain: "No token", code: 999, userInfo: nil), nil)))
//                        }
//                    }
//                }
//            }else {
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
                self.networkable = true
            default:
                self.networkable = false
            }
        })
    }
    
    
    @discardableResult func request(_ target: NetowrkReqeustApi, completion: @escaping Completion) -> Cancellable {
        
        return provider.request(target) { result in
            switch result {
            case .success(let respond):
                do {
                    let json = try respond.filter(statusCode: 200).mapJSON() as? [String: Any]
                    // 服务器返回成功
                    let code = JSON(json as Any)["code"].intValue
                    let isSuccess = JSON(json as Any)["isSuccess"].bool ?? false
                    if code == 200 || isSuccess {
                        completion(.success(json!))
//                        success?(json!)
                    }else {
                        
                        completion(.failure(.init(code: code)))
//                        if code == 4001 { // token过期
//                            userTokenExpiredDispose()
//                        }
                    }
                } catch let error {
                    let errorCode = (error as NSError).code
                    completion(.failure(.init(code: errorCode)))
                }
            case .failure(let error):
                let errorCode = (error as NSError).code
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
    
//    public typealias RawValue = MoyaError
    
    var code: Int {
        switch self {
        case .unknown:
            return 9999
        case .noNetwork:
            return -1009
        case .requestTimeout:
            return -1001
        case .noPermission:
            return 7000
        }
    }
    
    init(code: Int) {
        switch code {
        case -1009:
            self = .noNetwork
        case -1001:
            self = .requestTimeout
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
    /// 无权限
    case noPermission
}

extension NetworkApiError: LocalizedError {
    
    public var errorDescription: String? {
        switch self {
        case .noNetwork:
            return "phone_no_network".localizedString
        case .requestTimeout:
            return "network_request_timeout".localizedString
        case .noPermission:
            return "no_permission".localizedString
        case .unknown:
            return "unknown_error".localizedString
        }
    }
}
