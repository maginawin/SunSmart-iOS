//
//  Date+Extension.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/23.
//

import Foundation

extension Date {
    
    /// 获取预期的日期
    /// - Parameters:
    ///   - year: 年+-
    ///   - month: 月+-
    ///   - day: 日+-
    /// - Returns: 预期日期
    func getExpectDate(year: Int, month: Int, day: Int) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        var dateComponents = DateComponents()
        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = day
        let newDate = calendar.date(byAdding: dateComponents, to: self)
        return newDate ?? Date()
    }
    
    /// 根据Date提取年月日时间戳、时分秒时间戳
    func splitTimestamp() -> (dateTimestamp: TimeInterval, timeTimestamp: TimeInterval) {
        let calendar = Calendar.current
        
        // 1. 提取年月日（日期部分）
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: self)
        let dateOnly = calendar.date(from: dateComponents)!
        let dateTimestamp = dateOnly.timeIntervalSince1970
        
        // 2. 提取时分秒（时间部分）
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: self)
        let timeInterval = TimeInterval(timeComponents.hour! * 3600 +
                                      timeComponents.minute! * 60 +
                                      timeComponents.second!)
        
        return (dateTimestamp, timeInterval)
    }
    
}
