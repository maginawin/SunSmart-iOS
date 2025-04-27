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
        if timestamp > UInt32.max {
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
    
    /// 获取对应时间信息
    static func getAloneTime(timestamp: String, componentType : Calendar.Component) -> Int {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) ?? 0)
        let timeInt = Calendar.current.component(componentType, from: date)
        return timeInt
    }
    
    /// 获取对应年
    static func getTimeStringYear(timestamp : String) -> Int {
        
        return self.getAloneTime(timestamp: timestamp, componentType: .year)
    }
    
    /// 获取月份
    static func getTimeStringMonth(timestamp : String) -> Int {
        
        return self.getAloneTime(timestamp: timestamp, componentType: .month)
    }
    
    /// 获取日
    static func getTimeStringDay(timestamp : String) -> Int {
        return self.getAloneTime(timestamp: timestamp, componentType: .day)
    }
    
    /// 获取对应时
    static func getTimeStringHour(timestamp : String) -> Int {
        return self.getAloneTime(timestamp: timestamp, componentType: .hour)
    }
    
    /// 获取对应分
    static func getTimeStringMinute(timestamp : String) -> Int {
        return self.getAloneTime(timestamp: timestamp, componentType: .minute)
    }
}
