//
//  FirmwareVersionData.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/9/3.
//

import Foundation

struct FirmwareVersionData {
    
    /// 设备类型
    let deviceType: String
    /// 下载路径
    let firmwarePath: String
    
    /// 固件版本
    let version: String
    /// 固件大小(byte)
    let size: Int
    /// 固件更新时间戳
    let releaseTime: String
    /// 更新内容
    let content: String
    
    
    
    /// 固件大小字符
    var sizeStr: String {
        return String(format: "%.1fKB", Float(size) / 1024.0)
    }
    /// 更新时间
    var timeStr: String {
        return String.dateConvert(timestamp: releaseTime, dateFormat: "MMM dd, yyyy")
    }
    
}
