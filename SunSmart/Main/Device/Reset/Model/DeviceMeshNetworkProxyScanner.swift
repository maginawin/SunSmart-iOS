//
//  DeviceMeshNetworkProxyScanner.swift
//  SunSmart
//
//  Created by yuankehong on 2025/10/23.
//

import Foundation
import NordicSigMeshSDK
import CoreBluetooth

/// 简化的扫描器
class DeviceMeshNetworkProxyScanner {
    
    typealias ScanFinishedCallback = ((ProvisioningDevice?)->Void)
    
    private let networkId: String
    private let continuation: ScanFinishedCallback
    private var timeoutTimer: BackgroundTimer?
    private var optimizationTimer: BackgroundTimer?
    private var networkDevices: [ProvisioningDevice] = []
    private var isCompleted = false
    
    init(networkId: String, result: @escaping ScanFinishedCallback) {
        self.networkId = networkId
        self.continuation = result
    }
    
    func startScan() {
        // 超时定时器
        timeoutTimer = BackgroundTimer.scheduledTimer(withTimeInterval: 10, repeats: false, queue: .main) { [weak self] _ in
            self?.complete(nil)
        }
        
        // 开始扫描
        MeshLibManager.manager.scanDevice(withServices: [MeshProxyService.uuid]) {
            [weak self] peripheral, advertisementData, rssi in
            self?.handleDevice(peripheral: peripheral, advertisementData: advertisementData, rssi: rssi)
        }
    }
    
    private func handleDevice(peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        guard !isCompleted,
              let device = ProvisioningDevice(peripheral: peripheral, advertisementData: advertisementData, rssi: rssi),
              device.macAddress != nil,
              device.address > 0,
              device.networkId == networkId else { return }
        
        // -70dB信号以内直接选择设备
        if device.rssi.intValue >= -70 {
            complete(device)
        } else {
            // 去重添加设备
            if !networkDevices.contains(where: { $0.macAddress == device.macAddress }) {
                networkDevices.append(device)
            }
            
            // 启动优化定时器
            if optimizationTimer == nil {
                optimizationTimer = BackgroundTimer.scheduledTimer(withTimeInterval: 3, repeats: false, queue: .main) {
                    [weak self] _ in
                    let bestDevice = self?.networkDevices.sorted { $0.rssi.intValue > $1.rssi.intValue }.first
                    self?.complete(bestDevice)
                }
            }
        }
    }
    
    private func complete(_ device: ProvisioningDevice?) {
        guard !isCompleted else { return }
        isCompleted = true
        
        MeshLibManager.manager.stopScan()
        timeoutTimer?.invalidate()
        optimizationTimer?.invalidate()
        continuation(device)
    }
    
    deinit {
        MeshLibManager.manager.stopScan()
        timeoutTimer?.invalidate()
        optimizationTimer?.invalidate()
    }
}
