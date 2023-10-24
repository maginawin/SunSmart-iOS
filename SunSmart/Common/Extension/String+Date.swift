//
//  String+Date.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/25.
//

import Foundation

extension String {
    
    
    /// 时间戳字符串转时间（毫秒）
    /// - Parameters:
    ///   - millisecond: 毫秒
    ///   - dateFormat: 时间格式
    /// - Returns: 时间
    static func dateConvert(timestamp millisecond: String, dateFormat: String) -> String {
        guard let timestamp = CLongLong(millisecond) else {
            return millisecond
        }
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = dateFormat
        formatter.locale = Locale.current
        formatter.amSymbol = "am".localizedString
        formatter.pmSymbol = "pm".localizedString
//        Locale.init(identifier: "zh_Hans_CN")
        let timeStr = formatter.string(from: date)
        return timeStr
    }
    
}
