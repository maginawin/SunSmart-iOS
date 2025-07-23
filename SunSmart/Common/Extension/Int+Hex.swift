//
//  Int+Hex.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/5/23.
//

import Foundation

extension UInt8 {
    
    init?(hex: String) {
        guard hex.count == 2, let value = UInt8(hex, radix: 16) else {
            return nil
        }
        self = value
    }
    
    var hex: String {
        return String(format: "%02X", self)
    }
    
    init(data: Data) {
        self = data[0]
    }
    
    var data: Data {
        return Data([self])
    }
    
}

extension Int8 {
    
    init?(hex: String) {
        guard hex.count == 2, let value = UInt8(hex, radix: 16) else {
            return nil
        }
        self = Int8(bitPattern: value)
    }
    
    var hex: String {
        // This is to ensure that even negative numbers are printed with length 2.
        return String(String(format: "%02X", self).suffix(2))
    }
    
    init(data: Data) {
        self = Int8(bitPattern: data[0])
    }
    
    var data: Data {
        return Data([UInt8(bitPattern: self)])
    }
    
}

extension UInt16 {
    
    init?(hex: String) {
        guard hex.count == 4, let value = UInt16(hex, radix: 16) else {
            return nil
        }
        self = value
    }
    
    var hex: String {
        return String(format: "%04X", self)
    }
    
    init(data: Data) {
        self = data.withUnsafeBytes { $0.load(as: UInt16.self) }
    }
    
    var data: Data {
        var int = self
        return Data(bytes: &int, count: MemoryLayout<UInt16>.size)
    }
    
}

extension Int16 {
    
    init?(hex: String) {
        guard hex.count == 4, let value = UInt16(hex, radix: 16) else {
            return nil
        }
        self = Int16(bitPattern: value)
    }
    
    var hex: String {
        // This is to ensure that even negative numbers are printed with length 4.
        return String(String(format: "%04X", self).suffix(4))
    }
    
    init(data: Data) {
        self = data.withUnsafeBytes { $0.load(as: Int16.self) }
    }
    
    var data: Data {
        var int = self
        return Data(bytes: &int, count: MemoryLayout<Int16>.size)
    }
    
}

extension UInt32 {
    
    init?(hex: String) {
        guard hex.count == 8, let value = UInt32(hex, radix: 16) else {
            return nil
        }
        self = value
    }
    
    var hex: String {
        return String(format: "%08X", self)
    }
    
    init(data: Data) {
        self = data.withUnsafeBytes { $0.load(as: UInt32.self) }
    }
    
    var data: Data {
        var int = self
        return Data(bytes: &int, count: MemoryLayout<UInt32>.size)
    }
    
}

extension Int32 {
    
    init?(hex: String) {
        guard hex.count == 8, let value = UInt32(hex, radix: 16) else {
            return nil
        }
        self = Int32(bitPattern: value)
    }
    
    var hex: String {
        return String(format: "%08X", self)
    }
    
    init(data: Data) {
        self = data.withUnsafeBytes { $0.load(as: Int32.self) }
    }
    
    var data: Data {
        var int = self
        return Data(bytes: &int, count: MemoryLayout<Int32>.size)
    }
    
}

extension BinaryFloatingPoint {
    
    /// 转成精简字符串 maxDigits:最大保留几位小数
    func toSimplifyStr(maxDigits: Int) -> String {
        
        // 格式化逻辑
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = maxDigits // 最多保留 ? 位小数
        formatter.minimumFractionDigits = 0 // 最少保留 0 位小数（去掉多余的零）
//        formatter.roundingMode = .up
        formatter.groupingSeparator = ""
        let number = NSNumber(value: Double(self))
        guard let formattedString = formatter.string(from: number) else {
            return "\(self)"
        }
        return "\(formattedString)"
    }
}

extension Float {
    
    /// 精确两位小数，小数位四舍五入
    var roundf2: Float {
        return roundf(self * 100) / 100.0
    }
}

protocol PercentageProtocol {
    var percentage: UInt8 { get }
    var value16: UInt16 { get }
}

extension UInt8: PercentageProtocol {
    
    /// UInt8 => 0~100%
    var percentage: UInt8 {
        return UInt8((Double(self) / 2.55).rounded())
    }
    
    /// 0~100% => UInt16 value
    var value16: UInt16 {
        return UInt16(Double(self) / 100.0 * Double(UInt16.max))
    }
}

extension UInt16: PercentageProtocol {
    
    /// UInt16 => 0~100%
    var percentage: UInt8 {
        return UInt8((Double(self) / 65535.0 * 100.0).rounded())
    }
    
    /// UInt16 => 0.0~100.0%
    var percentageFloat: Float {
        return roundf((Float(self) / 65535.0 * 100.0) * 10) / 10
    }
    
    var value16: UInt16 {
        return self
    }
}

extension Double: PercentageProtocol {
    var percentage: UInt8 {
        return UInt8(self.rounded())
    }
    
    /// 0.0~100.0% => UInt16 value
    var value16: UInt16 {
        return UInt16(Double(self) / 100.0 * Double(UInt16.max))
    }
}
