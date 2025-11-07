//
//  DeviceMeshNetworkResetHandle.swift
//  SunSmart
//
//  Created by yuankehong on 2025/10/23.
//

import Foundation
import NordicSigMeshSDK

class DeviceMeshNetworkResetHandle {
    
    /// mesh网络重置错误
    enum MeshNetworkResetError: Error {
        /// 扫描代理超时
        case scanProxyTimeout
        /// 重置失败
        case resetFailed
        /// 数据异常
        case dataException
    }
    
    /// 操作类型
    enum OperationType {
        /// 无
        case none
        /// 重置
        case reset
        /// 识别
        case identify
        /// 网络重置
        case networkReset
        /// 网络识别
        case networkIdentify
    }
    
    /// mesh网络操作-扫描到代理回调
    typealias MeshNetworkScanProxyCallback = ((ProvisioningDevice)->Void)
    
    /// 操作结果回调
    typealias Completion = (Result<Void, MeshNetworkResetError>)->Void
    
    private var networkId: String?
    private var proxyScanner: DeviceMeshNetworkProxyScanner?
    private var scanProxyCallback: MeshNetworkScanProxyCallback?
    private var completionCallback: Completion?
    private let broadcaster = BluetoothBroadcaster()
    private var boradcasterTimer: BackgroundTimer?
    /// 检查结果定时器
    private var checkResetTimer: BackgroundTimer?
    /// 操作类型
    private var operationType: OperationType = .none
    /// 重置的设备（单设备重置）
    private var resetDevice: ProvisioningDevice?
    
    // MARK: - Public
    
    
    /// 开始重置mesh网络内设备
    /// - Parameters:
    ///   - networkId: mesh网络/子网id
    ///   - scanProxy: 扫描到代理回调
    ///   - completion: 结果
    func startMeshNetworkReset(networkId: String, scanProxy: MeshNetworkScanProxyCallback? = nil, completion: @escaping Completion) {
        
        reset()
        self.operationType = .networkReset
        self.networkId = networkId
        self.scanProxyCallback = scanProxy
        self.completionCallback = completion
        scanNetworkProxyDevice()
    }
    
    
    /// 开始识别mesh网络内设备
    /// - Parameters:
    ///   - networkId: mesh网络/子网id
    ///   - scanProxy: 扫描到代理回调
    ///   - completion: 结果
    func startMeshNetworkIdentify(networkId: String, scanProxy: MeshNetworkScanProxyCallback? = nil, completion: @escaping Completion) {
        
        reset()
        self.operationType = .networkIdentify
        self.networkId = networkId
        self.scanProxyCallback = scanProxy
        self.completionCallback = completion
        scanNetworkProxyDevice()
    }
    
    /// 开始重置设备
    /// - Parameters:
    ///   - device: 设备
    ///   - completion: 结果回调
    func startDeviceReset(device: ProvisioningDevice, completion: @escaping Completion) {
        
        reset()
        self.resetDevice = device
        self.operationType = .reset
        self.completionCallback = completion
        startBroadcasting(broadcastType: .resetNode(address: device.address, macAddress: device.macAddress!))
    }
    
    /// 开始识别设备
    /// - Parameters:
    ///   - device: 设备
    ///   - completion: 结果回调
    func startDeviceIdentify(device: ProvisioningDevice, completion: @escaping Completion) {
        
        reset()
        self.operationType = .identify
        self.completionCallback = completion
        startBroadcasting(broadcastType: .identifyNode(address: device.address, macAddress: device.macAddress!, mode: .default, frequency: .default))
    }
    
    /// 扫描网络内代理设备
    private func scanNetworkProxyDevice() {
        guard let networkId = self.networkId else {
            completionCallback?(.failure(.dataException))
            reset()
            return
        }
        /// 找到网络内合适的代理
        proxyScanner = DeviceMeshNetworkProxyScanner(networkId: networkId, result: {[weak self] device in
            guard let self = self else { return }
            if let proxyDevice = device {
                // 发送广播包让代理设备接收
                if self.operationType == .networkIdentify {
                    self.scanProxyCallback?(proxyDevice)
                    self.startBroadcasting(broadcastType: .meshNetworkIdentify(proxyAddress: proxyDevice.address, macAddress: proxyDevice.macAddress!, mode: .default, frequency: .default))
                }else if self.operationType == .networkReset {
                    self.scanProxyCallback?(proxyDevice)
                    self.startBroadcasting(broadcastType: .meshNetworkReset(proxyAddress: proxyDevice.address, macAddress: proxyDevice.macAddress!))
                }else {
                    self.completionCallback?(.failure(.dataException))
                    self.reset()
                }
            }else {
                self.completionCallback?(.failure(.scanProxyTimeout))
                self.reset()
            }
        })
        proxyScanner?.startScan()
    }
    
    
    deinit {
        reset()
    }
    
    func reset() {
        operationType = .none
        MeshLibManager.manager.stopScan()
        broadcaster.stopBroadcasting()
        proxyScanner = nil
        networkId = nil
        scanProxyCallback = nil
        completionCallback = nil
        boradcasterTimer?.invalidate()
        boradcasterTimer = nil
        checkResetTimer?.invalidate()
        checkResetTimer = nil
        resetDevice = nil
    }
    
    /// 给代理设备发送广播包
    private func startBroadcasting(broadcastType: BroadcasterType) {
        guard self.operationType != .none else { return }
        broadcaster.startBroadcasting(type: broadcastType, interval: 0.5)
        
        boradcasterTimer?.invalidate()
        boradcasterTimer = BackgroundTimer.scheduledTimer(withTimeInterval: 5, repeats: false, queue: .main, block: {[weak self] timer in
            timer.invalidate()
            guard let self = self else { return }
            self.broadcaster.stopBroadcasting()
            
            switch self.operationType {
            case .none:
                break
            case .reset: // 查找设备是否重置成功
                self.checkDeviceResetResult()
            case .identify, .networkIdentify: // 识别完成
                self.completionCallback?(.success(()))
                self.reset()
            case .networkReset:
                // 发送重置网络广播完成，检查重置结果
                guard self.networkId != nil else {
                    self.completionCallback?(.failure(.dataException))
                    self.reset()
                    return
                }
                // 等待设备重置
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {[weak self] in
                    guard let self = self, self.operationType == .networkReset else { return }
                    self.checkMeshNetworkResetResult()
                }
                
            }
        })
    }
    
    /// 检查单个设备重置结果
    private func checkDeviceResetResult() {
        
        guard let resetDevice = self.resetDevice else {
            completionCallback?(.failure(.dataException))
            reset()
            return
        }
        
        checkResetTimer?.invalidate()
        // 检查结果定时器，10秒内发现设备已退网则成功
        checkResetTimer = BackgroundTimer.scheduledTimer(withTimeInterval: 10, repeats: false, queue: .main, block: {[weak self] timer in
            timer.invalidate()
            guard let self = self else { return }
            if self.operationType == .reset {
                self.completionCallback?(.failure(.resetFailed))
            }else {
                self.completionCallback?(.failure(.dataException))
            }
            self.reset()
        })
        
        MeshLibManager.manager.scanDevice(withServices: [MeshProvisioningService.uuid]) {[weak self] peripheral, advertisementData, rssi in
            guard let self = self,
                  let device = ProvisioningDevice(peripheral: peripheral, advertisementData: advertisementData, rssi: rssi) else {
                return
            }
            if resetDevice.macAddress == device.macAddress, self.operationType == .reset { // 发现设备已退网
                MeshLibManager.manager.stopScan()
                self.completionCallback?(.success(()))
                self.reset()
            }
        }
        
    }
    
    /// 检查网络重置设备结果
    private func checkMeshNetworkResetResult() {
        
        checkResetTimer?.invalidate()
        // 检查结果定时器，10秒内未发现网络存在设备则认为删除成功
        checkResetTimer = BackgroundTimer.scheduledTimer(withTimeInterval: 10, repeats: false, queue: .main, block: {[weak self] timer in
            timer.invalidate()
            guard let self = self else { return }
            if self.operationType == .networkReset {
                self.completionCallback?(.success(()))
            }else {
                self.completionCallback?(.failure(.dataException))
            }
            self.reset()
        })
        
        MeshLibManager.manager.scanDevice(withServices: [MeshProxyService.uuid]) {[weak self] peripheral, advertisementData, rssi in
            guard let self = self,
                  let device = ProvisioningDevice(peripheral: peripheral, advertisementData: advertisementData, rssi: rssi) else {
                return
            }
            if device.networkId == self.networkId { // 发现网络内还存在设备
                MeshLibManager.manager.stopScan()
                self.completionCallback?(.failure(.resetFailed))
                self.reset()
            }
        }
        
    }
    
    
}
