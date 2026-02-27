//
//  DeviceResetBroadcasterCentral.swift
//  SunSmart
//
//  Created by yuankehong on 2025/10/15.
//

import Foundation
import NordicSigMeshSDK

protocol DeviceResetBroadcasterCentralDelegate: AnyObject {
    
    /// 开始发送广播包回调
    func broadcasterCentral(_ broadcasterCentral: DeviceResetBroadcasterCentral, didSendBroadcaster broadcasterData: DeviceResetBroadcasterData)
    
    /// 发送广播包完成回调
    func broadcasterCentral(_ broadcasterCentral: DeviceResetBroadcasterCentral, didFinishedBroadcaster broadcasterData: DeviceResetBroadcasterData)
}

class DeviceResetBroadcasterCentral {
    
    /// 紧急等级
    enum PriorityLevel {
        /// 立即
        case promptly
        /// 默认
        case `default`
    }
    
    /// 蓝牙无定向广播包对象
    private let bluetoothBroadcaster = BluetoothBroadcaster()
    /// 广播包数据list
    private(set) var broadcasterDatas: [DeviceResetBroadcasterData] = []
    
    private let mutex = DispatchQueue(label: "broadcasterMutex")
    /// 广播包发送定时器
    private var broadcasterTimer: DispatchSourceTimer?
    /// 广播包持续时长
    private var duration: TimeInterval = 2
    /// 代理
    weak var delegate: DeviceResetBroadcasterCentralDelegate?
    
    init(delegate: DeviceResetBroadcasterCentralDelegate?) {
        self.delegate = delegate
    }
    
    deinit {
        print("销毁了")
//        stopBroadcasterCompleteTimer()
//        bluetoothBroadcaster.stopBroadcasting()
    }
    
    // MARK: - Public
        
    /// 添加广播包到队列
    /// - Parameters:
    ///   - broadcasterData: 广播包数据
    ///   - level: 等级
    func addBroadcaster(_ broadcasterData: DeviceResetBroadcasterData, level: PriorityLevel = .default) {
        
        mutex.sync {
            if level == .default { // 默认等级
                broadcasterDatas.append(broadcasterData)
            }else { // 紧急等级
                if broadcasterDatas.isEmpty {
                    broadcasterDatas.append(broadcasterData)
                }else {
                    // 如果存在多个任务时，排在第一个任务后面，防止第一个任务广播包发送中被中断
                    broadcasterDatas.insert(broadcasterData, at: 1)
                }
            }
        }
        if !bluetoothBroadcaster.broadcasting {
            startBroadcasting()
        }
    }
    
    
    
    
    /// 取消所有广播包发送
    func cancelAllBroadcaster() {
        
        mutex.sync {
            broadcasterDatas.removeAll()
        }
        
        bluetoothBroadcaster.stopBroadcasting()
        stopBroadcasterCompleteTimer()
    }
    
    /// 取消排队的广播包
    func cancelAwaitBroadcasters() {
        mutex.sync {
            // 除了第1个其它都取消
            if broadcasterDatas.count > 1 {
                broadcasterDatas.removeSubrange(1..<broadcasterDatas.count)
            }
        }
    }
    
    /// 取消对应广播包
    func cancelBroadcaster(data: DeviceResetBroadcasterData) {

        if let index = mutex.sync(execute: { broadcasterDatas.firstIndex(where: { $0.macAddress == data.macAddress && $0.broadcasterType.code == data.broadcasterType.code }) } ) {
            broadcasterDatas.remove(at: index)
            
            if index == 0 {
                stopBroadcasterCompleteTimer()
                // 停止广播
                bluetoothBroadcaster.stopBroadcasting()
                if broadcasterDatas.count > 0 {
                    startBroadcasting()
                }
            }
        }
    }
    
    /// 取消对应广播包
    func cancelBroadcaster(type: BroadcasterType) {

        if let index = mutex.sync(execute: { broadcasterDatas.firstIndex(where: { $0.broadcasterType == type }) } ) {
            broadcasterDatas.remove(at: index)
            
            if index == 0 {
                stopBroadcasterCompleteTimer()
                // 停止广播
                bluetoothBroadcaster.stopBroadcasting()
                if broadcasterDatas.count > 0 {
                    startBroadcasting()
                }
            }
        }
    }
    
    /// 取消identity广播包
    func cancelIdentifyBroadcaster() {
        
        /// 判断是否正在identity中
        var identifyBroadcastering: Bool = false
        mutex.sync(execute: {
            if let current = broadcasterDatas.first {
                switch current.broadcasterType {
                case .identifySensorNode, .identifyNode:
                    identifyBroadcastering = true
                default:
                    break
                }
            }
            broadcasterDatas.removeAll(where: { $0.broadcasterType.code == BroadcasterType.identifySensorNode(key: 0, macAddress: "").code || $0.broadcasterType.code == BroadcasterType.identifyNode(address: 0, macAddress: "", mode: .flash(count: 5)).code })
        })
        
        if identifyBroadcastering {
            stopBroadcasterCompleteTimer()
            // 停止广播
            bluetoothBroadcaster.stopBroadcasting()
            if broadcasterDatas.count > 0 {
                startBroadcasting()
            }
        }
        
    }
    
    // MARK: - Private
    
    /// 开启广播包发送完成定时器
    private func startBroadcasterCompleteTimer() {
        
        if broadcasterTimer != nil {
            broadcasterTimer?.cancel()
            broadcasterTimer = nil
        }

        // 创建定时器
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + self.duration)
        timer.setEventHandler { [weak self] in
            self?.sendBroadcasterEvent()
        }
        timer.resume()
        self.broadcasterTimer = timer
        
    }
    
    /// 关闭广播定时器
    private func stopBroadcasterCompleteTimer() {
        broadcasterTimer?.cancel()
        broadcasterTimer = nil
    }
    
    /// 定时器事件
    private func sendBroadcasterEvent() {
        
        // 停止广播
        bluetoothBroadcaster.stopBroadcasting()
        // 停止
        stopBroadcasterCompleteTimer()
        
        // 拿到队列中第一条数据
        guard let data = mutex.sync(execute: { broadcasterDatas.first }) else {
            return
        }
        
        DispatchQueue.main.async {
            self.delegate?.broadcasterCentral(self, didFinishedBroadcaster: data)
        }
        
        self.broadcasterDatas.removeFirst()
        // 检查完成后是否还有任务需要继续发送
        if self.broadcasterDatas.count > 0 {
            self.startBroadcasting()
        }
        
    }
    
    /// 开始发送广播包
    private func startBroadcasting() {
        
        // 拿到队列中第一条数据
        guard let data = mutex.sync(execute: { self.broadcasterDatas.first }) else {
            return
        }
        // 开始发送广播
        bluetoothBroadcaster.startBroadcasting(type: data.broadcasterType)
        // 开启发送广播包完成定时器
        startBroadcasterCompleteTimer()
        // 开始发送回调
        DispatchQueue.main.async {
            self.delegate?.broadcasterCentral(self, didSendBroadcaster: data)
        }
    }
    
    
    
}

/// 设备重置广播包数据
struct DeviceResetBroadcasterData {
    /// 设备mac地址
    let macAddress: String
    /// 广播包类型
    let broadcasterType: BroadcasterType
    
}
