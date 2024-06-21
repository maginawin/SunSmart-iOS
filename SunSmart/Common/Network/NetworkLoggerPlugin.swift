//
//  NetworkLoggerPlugin.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/6/13.
//

import Foundation
import Moya
import SwiftyJSON

final class NetworkLoggerPlugin: PluginType {

    // Called immediately before a request is sent over the network (or stubbed).
    func willSend(_ request: RequestType, target: TargetType) {
        print("🌐 Sending request to \(request.request?.url?.absoluteString ?? "unknown URL")")
        print("🌐 Request headers: \(request.request?.allHTTPHeaderFields ?? [:])")
        print("🌐 Request body: \(String(data: request.request?.httpBody ?? Data(), encoding: .utf8) ?? "no body")")
    }

    // Called after a response has been received, but before the completion handler is called.
    func didReceive(_ result: Result<Response, MoyaError>, target: TargetType) {
        switch result {
        case .success(let response):
//            guard let networkTarget = target as? NetowrkReqeustApi else { return }
//            
//            switch networkTarget {
//            case .siteAdd(let siteData):
//                
//            default:
//                <#code#>
//            }
            
            print("✅ Received response from \(response.request?.url?.absoluteString ?? "unknown URL")")
            print("✅ Response status code: \(response.statusCode)")
            print("✅ Response data: \(String(data: response.data, encoding: .utf8) ?? "no data")")
        case .failure(let error):
            print("❌ Request failed with error: \(error.localizedDescription)")
        }
    }
    
//    func process(_ result: Result<Response, MoyaError>, target: TargetType) -> Result<Response, MoyaError> {
        
        
        
//        switch result {
//        case .success(let respond):
//            do {
//                let json = try respond.filter(statusCode: 200).mapJSON() as? [String: Any]
//                // 服务器返回成功
//                let code = JSON(json as Any)["code"].intValue
//                let isSuccess = JSON(json as Any)["isSuccess"].bool ?? false
//                if code == 200 || isSuccess {
//                    success?(json!)
//                }else {
//                    failure?(NSError(domain: json?["message"] as? String ?? "", code: code))
//                    
////                        if code == 4001 { // token过期
////                            userTokenExpiredDispose()
////                        }
//                }
//            } catch let error {
//                failure?(error as NSError)
//            }
//        case .failure(let error):
//            switch error {
//            case .underlying(let resultError, _):
//                let requestError = (resultError as NSError)
//                failure?(requestError)
////                    if requestError.code == noInterNetworkCode { // 无网络提示
////                        showNoInterNetworkMessage()
////                    }else if requestError.code == networkRequestTimeoutCode { // 请求超时
////                        showNetworkTimeoutMessage()
////                    }
//            default:
//                failure?(error as NSError)
//            }
//        }
        
//    }
}
