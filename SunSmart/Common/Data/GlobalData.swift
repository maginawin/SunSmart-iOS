//
//  GlobalData.swift
//  SunSmart
//
//  Created by yuankehong on 2025/8/19.
//

import Foundation

/// 设备配置数据（添加、删除）
struct DeviceSettingsParameterData {
    
    static let `default`: DeviceSettingsParameterData = .init(brightness: 15, illuminationDelta: 50, notificationEnable: true, volume: 50, vibrationEnable: true)
    
    /// 亮度 0~100%
    let brightness: UInt8
    /// 光照lux差值
    let illuminationDelta: UInt16
    /// 手电筒闪烁频率
    var flashFrequency: UInt16 = 10
    /// 是否开启音频通知
    let notificationEnable: Bool
    /// 音量
    let volume: Int
    /// 是否开启震动
    let vibrationEnable: Bool
    
    /// 系统最低音量要求
    static let systemMinimumVolumeRequire: Float = 0.2
}

/// 参数
var deviceSettingsParameterData: DeviceSettingsParameterData = .default
/// 手电筒安全模式下参数
var flashlightSafeModeParameterData: DeviceSettingsParameterData = .default
/// 手电筒暴力模式下参数
var flashlightBeastModeParameterData: DeviceSettingsParameterData = .default
/// 移动感应模式下参数
var motionModeParameterData: DeviceSettingsParameterData = .default

