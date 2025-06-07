//
//  EnergyStatisticsStaticData.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/10.
//

import Foundation
import NordicSigMeshSDK

class EnergyStatisticsStaticData {
    
//    static let documentURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    
    /// 时间戳
    let timestamp: Int64
    /// 是否不完整的能耗数据（缺少部分设备）
    let incomplete: Bool
    /// 设备能耗数据
    let deviceEnergyDatas: [DeviceTotalEnergyData]
    /// 采集数据当时的组list
    let groups: [Group]
    
    private var _maxTotalEnergyUse: UInt64?
    /// 所有设备满功率总能耗(W/h)
    var maxTotalEnergyUse: UInt64 {
        get {
            if let value = _maxTotalEnergyUse {
                return value
            }
            let total = deviceEnergyDatas.reduce(UInt64(0)) { partial, energyData in
                partial + UInt64(energyData.maxTotalEnergyUse ?? 0)
            }
            _maxTotalEnergyUse = total
            return total
        }
    }
    
    private var _preciseTotalEnergyUse: UInt64?
    /// 所有设备实际使用总能耗(W/h)
    var preciseTotalEnergyUse: UInt64 {
        get {
            if let value = _preciseTotalEnergyUse {
                return value
            }
            let total = deviceEnergyDatas.reduce(UInt64(0)) { partial, energyData in
                partial + UInt64(energyData.preciseTotalEnergyUse ?? 0)
            }
            _preciseTotalEnergyUse = total
            return total
        }
    }
    
    private var _totalRatedPower: UInt32?
    /// 所有设备总额定功率（0.1W）
    var totalRatedPower: UInt32 {
        if let value = _totalRatedPower {
            return value
        }
        let total = deviceEnergyDatas.reduce(UInt32(0)) { partial, energyData in
            partial + UInt32(energyData.maxRatedPower ?? 0)
        }
        _totalRatedPower = total
        return total
    }
    
    /// 总计节约能耗（W）
    var energySaving: UInt64 {
        return UInt64(max(0, Int(maxTotalEnergyUse) - Int(preciseTotalEnergyUse)))
    }
    
    // 节约比例 %
    var energySavingPercentage: Float {
        return Float(Double(energySaving) / Double(max(maxTotalEnergyUse, 1)) * 100)
    }
    
    /// 初始化静态统计数据
    /// - Parameters:
    ///   - timestamp: 时间戳
    ///   - incomplete: 数据是否缺失
    ///   - deviceEnergyDatas: 设备能耗数据list
    init(timestamp: Int64, incomplete: Bool, deviceEnergyDatas: [DeviceTotalEnergyData], groups: [Group]) {
        self.timestamp = timestamp
        self.incomplete = incomplete
        self.deviceEnergyDatas = deviceEnergyDatas
        self.groups = groups
    }
    
    
    /// 转换为CSV文件
    /// - Parameters:
    ///   - spaceName: 空间名称
    ///   - fileName: 文件名
    /// - Returns: 文件URL
    func convertingCVSFile(spaceName: String, fileName: String) -> URL? {
        
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName).appendingPathExtension("csv")
        
        let csvString = self.toCSVString(spaceName: spaceName)
        do {
            try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("csv write error: \(error)")
            return nil
        }
    }
    
    /// 转成CSV字符串
    /// - Parameter spaceName: 空间名称
    /// - Returns: CSV字符串
    func toCSVString(spaceName: String) -> String {
        
        var csvText = "\("energy_data_reporting_timestamp".localizedString),\("node_id/name".localizedString),\("collection_status".localizedString),\("maximum_rated_power".localizedString),\("maximum_rated_energy_consumption".localizedString),\("energy_consumption".localizedString),\("energy_saving".localizedString),\("energy_saving_percentage".localizedString)\n"
        
        let totalRow = [
            String.dateConvert(timestamp: "\(self.timestamp)", dateFormat: "yyyy/M/d HH:mm"),
            "\(spaceName) (\("ALL".localizedString))",
            self.incomplete ? "incomplete_data".localizedString : "full_data".localizedString,
            String(format: "%.1f", Double(totalRatedPower) / 10),
//            (Double(self.totalRatedPower) / 10).toSimplifyStr(maxDigits: 1),
            String(format: "%.2f", Double(maxTotalEnergyUse) / 1000),
//            (Double(maxTotalEnergyUse) / 1000).toSimplifyStr(maxDigits: 2),
            String(format: "%.2f", Double(preciseTotalEnergyUse) / 1000),
//            (Double(preciseTotalEnergyUse) / 1000).toSimplifyStr(maxDigits: 2),
            String(format: "%.2f", Double(energySaving) / 1000),
//            (Double(energySaving) / 1000).toSimplifyStr(maxDigits: 2),
            String(format: "%.2f%%", energySavingPercentage),
//            "\(energySavingPercentage.toSimplifyStr(maxDigits: 2))%"
        ].joined(separator: ",")
        csvText += totalRow + "\n"
        
        for device in deviceEnergyDatas {
//            let maximumRatedPowerStr = device.maxRatedPower != nil ? (Double(device.maxRatedPower!) / 10).toSimplifyStr(maxDigits: 1) : ""
            let maximumRatedPowerStr = device.maxRatedPower != nil ? String(format: "%.1f", Double(device.maxRatedPower!) / 10) : ""
            
            var maximumRatedEnergyConsumptionStr = ""
            if let maxTotalEnergyUse = device.maxTotalEnergyUse {
                maximumRatedEnergyConsumptionStr = String(format: "%.2f", Double(maxTotalEnergyUse) / 1000)
//                (Double(maxTotalEnergyUse) / 1000).toSimplifyStr(maxDigits: 2)
            }
            
            var energyConsumptionStr = ""
            if let preciseTotalEnergyUse = device.preciseTotalEnergyUse {
                energyConsumptionStr = String(format: "%.2f", Double(preciseTotalEnergyUse) / 1000)
//                (Double(preciseTotalEnergyUse) / 1000).toSimplifyStr(maxDigits: 2)
            }
            
            var energySavingStr = ""
            if device.preciseTotalEnergyUse != nil, device.maxTotalEnergyUse != nil {
                energySavingStr = String(format: "%.2f", Double(device.energySaving) / 1000)
//                (Double(device.energySaving) / 1000).toSimplifyStr(maxDigits: 2)
            }
            
            var energySavingPercentageStr = ""
            if device.preciseTotalEnergyUse != nil, device.maxTotalEnergyUse != nil {
                energySavingPercentageStr = String(format: "%.2f%%", device.energySavingPercentage)
//                "\(device.energySavingPercentage.toSimplifyStr(maxDigits: 2))%"
            }
            
            let row = [
                String.dateConvert(timestamp: "\(device.timestamp)", dateFormat: "yyyy/M/d HH:mm"),
                device.name,
                device.state.rawCSVString,
                maximumRatedPowerStr,
                maximumRatedEnergyConsumptionStr,
                energyConsumptionStr,
                energySavingStr,
                energySavingPercentageStr
            ].joined(separator: ",")
            
            csvText += row + "\n"
        }
        return csvText
    }
    
//    static func loadAll(spaceId: String) -> [EnergyStatisticsStaticData] {
//
//        var staticDatas: [EnergyStatisticsStaticData] = []
//        let staticDataFileURL = documentURL.appendingPathComponent("Energy/\(spaceId)/StaticData")
//        do {
//            let fileURLs = try FileManager.default.contentsOfDirectory(at: staticDataFileURL, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey], options: .skipsHiddenFiles)
//            
//            for fileURL in fileURLs {
//                let resourceValues = try fileURL.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
//                
//                let
//                
//            }
//            
//        } catch {
//            print("❌ Error reading static data directory: \(error)")
//        }
////        Doucument/Energy/‘spaceId’/StaticData
//    }
    
}


class DeviceTotalEnergyData: Codable {
    
    /// 状态
    enum State: Int, Codable {
        /// CSV状态字符
        var rawCSVString: String {
            switch self {
            case .success:
                return "templates_normal".localizedString
            case .failed:
                return "incomplete_data".localizedString
            case .notSetPower:
                return "invalid_power_value".localizedString
            }
        }
        
        /// 采集成功
        case success = 0
        /// 采集失败
        case failed = 1
        /// 未设置功率
        case notSetPower = 2
    }
    
    /// 设备名称
    let name: String
    /// 设备地址
    let address: Address
    /// 设备pid
    let productId: UInt16?
    /// 设备采集数据时所在的组
    let groupAddress: Address?
    /// 时间戳
    let timestamp: Int64
    /// 最大输出功率(0.1W)
    let maxRatedPower: UInt16?
    /// 满功率使用的总能耗（W/h）
    let maxTotalEnergyUse: UInt32?
    /// 实际使用的总能耗（W/h）
    let preciseTotalEnergyUse: UInt32?
    /// 状态
    let state: State
    /// 图标名称
    var iconName: String? {
        let deviceInfo = MeshLibManager.manager.supportDeviceInfos.first(where: { $0.productId == productId })
        return "device_\(deviceInfo?.iconCategory ?? "unknown")"
    }
    
    /// 总计节约能耗（W）
    var energySaving: UInt32 {
        guard let maxTotalEnergyUse = maxTotalEnergyUse, let preciseTotalEnergyUse = preciseTotalEnergyUse else { return 0 }
        return UInt32(max(0, Int(maxTotalEnergyUse) - Int(preciseTotalEnergyUse)))
    }
    
    // 节约比例
    var energySavingPercentage: Float {
        guard let maxTotalEnergyUse = maxTotalEnergyUse else {
            return 0
        }
        return Float(Double(energySaving) / Double(max(maxTotalEnergyUse, 1)) * 100)
    }
    
    init(name: String, address: Address, productId: UInt16?, groupAddress: Address?, timestamp: Int64, maxRatedPower: UInt16?, maxTotalEnergyUse: UInt32?, preciseTotalEnergyUse: UInt32?, state: State) {
        self.name = name
        self.address = address
        self.productId = productId
        self.groupAddress = groupAddress
        self.timestamp = timestamp
        self.maxRatedPower = maxRatedPower
        self.maxTotalEnergyUse = maxTotalEnergyUse
        self.preciseTotalEnergyUse = preciseTotalEnergyUse
        self.state = state
    }
    
}
