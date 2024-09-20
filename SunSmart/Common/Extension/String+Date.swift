//
//  String+Date.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/25.
//

import Foundation

extension String {
    
    
    /// 时间戳字符串转时间
    /// - Parameters:
    ///   - millisecond: 秒/毫秒
    ///   - dateFormat: 时间格式
    /// - Returns: 时间
    static func dateConvert(timestamp millisecond: String, dateFormat: String) -> String {
        guard var timestamp = CLongLong(millisecond) else {
            return millisecond
        }
        if timestamp > CLongLong(Date().timeIntervalSince1970) {
            timestamp = CLongLong(Double(timestamp) / 1000.0)
        }
        let date = Date(timeIntervalSince1970: Double(timestamp))
        let formatter = DateFormatter()
        formatter.dateFormat = dateFormat
        formatter.locale = Locale.current
        formatter.amSymbol = "am".localizedString
        formatter.pmSymbol = "pm".localizedString
//        Locale.init(identifier: "zh_Hans_CN")
        let timeStr = formatter.string(from: date)
        return timeStr
    }
    
    /// 时间字符串转时间戳
    /// - Parameters:
    ///   - timeStr: 时间字符串
    ///   - dateFormat: 时间格式
    /// - Returns: 时间戳
    static func dateConvert(timeStr: String, dateFormat: String?) -> Int64 {
       
        let formatter = DateFormatter.init()
        formatter.dateFormat = dateFormat ?? "YYYY-MM-dd HH:mm:ss"
        let date = formatter.date(from: timeStr) ?? Date()
        return Int64(date.timeIntervalSince1970)
    }
    
}
