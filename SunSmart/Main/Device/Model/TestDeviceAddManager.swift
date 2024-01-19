//
//  TestDeviceAddManager.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/1/12.
//

import Foundation
import NordicSigMeshSDK

class TestDeviceAddManager: NSObject {
    
    static let manager = TestDeviceAddManager()
    
    /// 待添加设备操作list
    private var awaitOperations: [TestDeviceAddOperation] = []
    /// 添加中设备操作list
    private var addingOperations: [TestDeviceAddOperation] = []
    /// 添加成功的设备操作list
    private var successOperations: [TestDeviceAddOperation] = []
    /// 添加失败的设备操作list
    private var failOperations: [TestDeviceAddOperation] = []
    
    /// 设备开始添加回调
    private var deviceStartAddBack : deviceStartAddBlock?
    /// 设备连接成功回调
    private var deviceConnectingBack : deviceStartAddBlock?
    /// 设备添加成功回调
    private var deviceAddSuccessBack : deviceConnectedBlock?
    
    /// 设备添加失败回调
    private var deviceAddFailBack : deviceAddFailBlock?
    /// 设备添加完成回调
    private var deviceAddFinishBack : deviceAddFinishBlock?

    /// 是否正在添加设备中
    var isAdding: Bool = false
    let maxOperationCount = 5
    
    /// 批量添加设备
    /// - Parameters:
    ///   - mustKeybindFinish: 是否必须完成节点功能绑定（false：不强制有部分功能需后面再绑定，否则未绑定model不可用； true：节点功能绑定失败则重置节点）
    ///   - addDeviceList: 需添加的设备list
    ///   - startAddBack: 设备开始添加回调
    ///   - connectingBack: 设备连接成功回调
    ///   - appendMessagesBack: 设备添加操作完成后需要追加的消息（添加成功回调前发送）
    ///   - addSuccessBack: 设备添加成功回调（每个设备成功都会回调）
    ///   - addFailBack: 设备添加失败回调（每个设备失败都会回调）
    ///   - addFinishBack: 设备添加完成回调（全部添加完成回调）
    func startAddDevices(mustKeybindFinish: Bool = false, addDeviceList: [ProvisioningDevice], startAddBack: deviceStartAddBlock?, connectingBack: deviceConnectedBlock? = nil, addSuccessBack:deviceAddSuccessBlock?, addFailBack:deviceAddFailBlock?, addFinishBack:deviceAddFinishBlock?) {
     
        let addOperations = addDeviceList.map {
            TestDeviceAddOperation(device: $0) {[weak self] operation in
                self?.deviceStartAddBack?(operation.device)
            } connectedBack: {[weak self] operation in
                self?.deviceConnectingBack?(operation.device)
            } addSuccessBack: {[weak self] operation in
                self?.deviceAddSuccessBack?(operation.device)
                self?.successOperations.append(operation)
                self?.addingOperations.removeAll(where: { $0.device == operation.device })
                self?.startAddOperation()
            } addFailBack: {[weak self] operation, error in
                self?.deviceAddFailBack?(operation.device, error)
                self?.failOperations.append(operation)
                self?.addingOperations.removeAll(where: { $0.device == operation.device })
                self?.startAddOperation()
            }
        }
        
        // 是否正在添加设备
        if isAdding {
            // 添加中则追加需添加的设备
            awaitOperations.append(contentsOf: addOperations)
            // 失败的设备重新添加则从失败操作list中删除
            failOperations.removeAll { failOperation in
                return addOperations.contains(where: { $0.device == failOperation.device })
            }
            startAddOperation()
            return
        }
    
        isAdding = true
        
        awaitOperations.removeAll()
        addingOperations.removeAll()
        successOperations.removeAll()
        failOperations.removeAll()
        
        deviceStartAddBack = startAddBack
        deviceConnectingBack = connectingBack
        deviceAddSuccessBack = addSuccessBack
        deviceAddFailBack = addFailBack
        deviceAddFinishBack = addFinishBack
        awaitOperations = addOperations
    
        startAddOperation()
        
    }
    
    /// 取消正在排队的设备（添加中的设备正常进行，取消排队的设备）
    func cancelAwaitOperations() {
        awaitOperations.removeAll()
    }
    
    /// 取消正在排队的设备（添加中的设备正常进行，取消排队的设备）
    /// - Parameter devices: 根据外部传入的设备取消对应的操作
    func cancelAwaitOperations(devices: [ProvisioningDevice]) {
        // 取消排队
        awaitOperations.removeAll(where: { devices.contains($0.device) })
    }
    
    /// 停止添加设备
    /// - Parameter finishBack: 添加结果回调 返回成功设备、失败设备
    func stopAddDevice(finishBack:deviceAddFinishBlock?) {
        guard isAdding else {
            DispatchQueue.main.async {
                finishBack?([], [])
            }
            return
        }
        isAdding = false
        // 中断排队和添加中设备都算失败
        self.awaitOperations.forEach({ $0.stop() })
        self.addingOperations.forEach({ $0.stop() })
        let successDevices = self.successOperations.map({ $0.device })
        let failDevices = self.failOperations.map({ $0.device })
        DispatchQueue.main.async {
            finishBack?(successDevices, failDevices)
            self.reset()
        }
    }
    
    /// 检查添加设备操作
    private func startAddOperation() {
        
//        maxOperationCount
//        let connectCount = MeshLibManager.manager.getConnectedPeripherals().count
//        let canAdd = maxOperationCount - max(addingOperations.count, MeshLibManager.manager.getConnectedPeripherals().count) > 0
        while isAdding, awaitOperations.count > 0 && maxOperationCount - max(addingOperations.count, MeshLibManager.manager.getConnectedPeripherals().count) > 0 {
            // addingOperations.count < maxOperationCount
            let operation = awaitOperations.first!
            addingOperations.append(operation)
            operation.start()
            
            awaitOperations.removeFirst()
        }
        
        // 无设备可添加（完成）
        if addingOperations.isEmpty {
            let successDevices = successOperations.map({ $0.device })
            let failDevices = failOperations.map({ $0.device })
            deviceAddFinishBack?(successDevices, failDevices)
            
            reset()
        }
        
    }
    
    /// 重置数据
    private func reset() {
        

        deviceStartAddBack = nil
        deviceAddSuccessBack = nil
        deviceAddFailBack = nil
        deviceAddFinishBack = nil
        
        awaitOperations.removeAll()
        addingOperations.removeAll()
        successOperations.removeAll()
        failOperations.removeAll()
        
        isAdding = false
        
    }
    
}

class TestDeviceAddOperation: NSObject {
    
    /// 添加进程
    enum AddStep {
        /// 无
        case none
        /// 连接中
        case connecting
        /// 配网中
        case provisioning
        /// 绑定设备中
        case keybind
    }
    
    /// 开始添加回调
    typealias DeviceStartOperationCallback = (TestDeviceAddOperation)->Void
    /// 连接成功回调
    typealias DeviceOperationConnectedCallback = (TestDeviceAddOperation)->Void
    /// 添加成功回调
    typealias DeviceOperationSuccessCallback = (TestDeviceAddOperation)->Void
    /// 添加失败回调
    typealias DeviceOperationFailCallback = (TestDeviceAddOperation, NSError)->Void
    
    /// 正在配网的设备
    let device : ProvisioningDevice
    
    /// 设备添加成功回调
    private var deviceAddSuccessBack : DeviceStartOperationCallback?
    /// 设备开始添加回调
    private var deviceStartAddBack : DeviceOperationSuccessCallback?
    /// 设备连接成功回调
    private var deviceConnectedBack: DeviceOperationConnectedCallback?
    /// 设备添加失败回调
    private var deviceAddFailBack : DeviceOperationFailCallback?
    
    private var timer: Timer?
    private var addStep: AddStep = .none

    /// 初始化添加设备操作
    /// - Parameters:
    ///   - device: 需添加的设备
    ///   - startAddBack: 设备开始添加回调
    ///   - capabilitiesReceivedBack: 收到设备配网参数回调
    ///   - addSuccessBack: 设备添加成功回调
    ///   - addFailBack: 设备添加失败回调
    init(device: ProvisioningDevice, startAddBack: DeviceStartOperationCallback?, connectedBack: DeviceOperationConnectedCallback?, addSuccessBack:DeviceOperationSuccessCallback?, addFailBack:DeviceOperationFailCallback?) {
        self.device = device
        super.init()
 
//        provisioningManager = ProvisioningManager(for: unprovisionedDevice, over: provisioningBearer, in: network)
        
        deviceStartAddBack = startAddBack
        deviceConnectedBack = connectedBack
        deviceAddSuccessBack = addSuccessBack
        deviceAddFailBack = addFailBack

    }
    
    /// 开始添加
    public func start() {
        
        deviceStartAddBack?(self)
        startConnect()
    }
    /// 停止添加
    public func stop() {
        timer?.invalidate()
        timer = nil
        if addStep == .keybind {
            deviceAddSuccessBack?(self)
        }else {
            deviceAddFailBack?(self, NSError(domain: "stop", code: 0))
        }
    }
    
    private func startConnect() {
        let interval = 1 + Double(arc4random_uniform(2000)) / 1000.0
        addStep = .connecting
        startTimer(timeInterval: interval) {[weak self] in
            guard let self = self else { return }
            self.deviceConnectedBack?(self)
            self.startProvisioning()
        }
    }
    
    private func startProvisioning() {
        addStep = .provisioning
        let interval = 0.5 + Double(arc4random_uniform(1000)) / 1000.0
        startTimer(timeInterval: interval) {[weak self] in
            guard let self = self else { return }
//            self.device?(self)
            self.startKeyBind()
        }
    }
    
    private func startKeyBind() {
        addStep = .keybind
        let interval = 1.5 + Double(arc4random_uniform(2000)) / 1000.0
        startTimer(timeInterval: interval) {[weak self] in
            guard let self = self else { return }
            self.deviceAddSuccessBack?(self)
        }
    }
    
    private func startTimer(timeInterval: TimeInterval, callback: @escaping (()->Void)) {
        
        timer?.invalidate()
        timer = Timer(timeInterval: timeInterval, repeats: false, block: { _ in
            callback()
        })
        RunLoop.current.add(timer!, forMode: .common)
    }
    
}
