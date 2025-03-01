//
//  DeviceRestoreViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/11/22.
//

import UIKit
import NordicSigMeshSDK

class DeviceRestoreViewController: UIViewController {

    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Restore"
        
        view.backgroundColor = Background_Color
        
        MeshAPI.startScanRecoverDevices(duration: 10) { device, node in
            
            if node.macAddress == "E43703BA05EE" {
                let name = node.name ?? device.deviceName ?? ""
                let group = node.group
                
                MeshAPI.startFastAddDevices(devices: [device]) { [weak self] addDevice in
                    print("开始添加:\(name)")
//                    addDevice.addState = .addConnecting
//                    self?.reloadDeviceState(addDevice)
//                    self?.updateUIState()
                } connectingBack: {[weak self] addDevice in
                    print("开始连接:\(name)")
                } appendMessagesBack: {[weak self] addDevice in
                    guard let self = self, let newNode = MeshNetworkManager.instance.meshNetwork?.node(withAddress: addDevice.address) else { return [] }
                    var appendMessages: [MeshMessageHandle] = []
                    
                    if let addGroup = group {
                        appendMessages.append(contentsOf: newNode.getResoreMessageHandles(oldNode: node, group: addGroup))
                        node.deleteExtension()
                        
                    }else {
                        if let vendorModel = newNode.sunricherVendorModel { // 未加入组的设备默认设置一个手动控制延迟时间，避免默认30s后状态被LC修改
                            appendMessages.append(MeshMessageHandle(message: SunricherVendorSet(function: .manualOverrideTimeout(enabled: true, state: .standby, interval: .max)), model: vendorModel))
                        }
                        if let powerOnOffSetupModel = newNode.powerOnOffSetupModel { // 设置默认上电状态
                            appendMessages.append(MeshMessageHandle(message: GenericOnPowerUpSet(state: .restore), model: powerOnOffSetupModel))
                        }
                    }
                    // 需要追加发送的消息
                    if let ctlModel = newNode.ctlModel, newNode.temperatureModel != nil {
                        appendMessages.insert(MeshMessageHandle(message: LightCTLTemperatureRangeGet(), model: ctlModel), at: 0)
                    }
                    // 设置默认过渡时间
        //            if let defaultTransitionTimeModel = node.defaultTransitionTimeModel {
        //                appendMessages.append(MeshMessageHandle(message: GenericDefaultTransitionTimeSet(transitionTime: .default), model: defaultTransitionTimeModel))
        //            }
                    // 节点数据hash
                    if let vendorModel = newNode.sunricherVendorModel {
                        appendMessages.append(MeshMessageHandle(message: SunricherVendorGet(function: .compositionHash), model: vendorModel))
                    }
                    // 添加成功后闪烁
                    if let healthModel = newNode.healthModel {
                        appendMessages.append(MeshMessageHandle(message: AttentionSet(attentionTimer: 6), model: healthModel))
                    }
                    
                    
        //            appendMessages.insert(MeshMessageHandle(message: ConfigRelaySet(), address: node.primaryUnicastAddress), at: 0)
                    
                    // 获取对应传感器model，识别传感器类型
        //            node.sensorModels.forEach { sensorModel in
        //                appendMessages.append(MeshMessageHandle(message: SensorGet(), model: sensorModel))
        //            }
                    return appendMessages
                } appendMessageSuccessBack: { messageHandle in
                    // 发送扩展消息成功更新缓存数据
                    if let address = messageHandle.model?.parentElement?.unicastAddress ?? messageHandle.address, let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) {
                        
                        // 设置光感传感器publish
//                        if let publicationMessage = messageHandle.message as? ConfigModelPublicationSet, publicationMessage.modelIdentifier == node.ambientLightSensorModel?.modelIdentifier, publicationMessage.elementAddress == node.ambientLightSensorModel?.parentElement?.unicastAddress, node.sensorCalibrated {
//                            node.group?.info.ambientLightSensorNodeAddress = node.primaryUnicastAddress
//                            node.group?.info.save()
//                        }
                        
                        DispatchQueue.global().async {
                            node.updateData(message: messageHandle.message)
                        }
                    }
                } addSuccess: {[weak self] addDevice in
                    guard let self = self else { return }
                    print("添加成功")
                    if let newNode = MeshNetworkManager.instance.meshNetwork?.node(withAddress: addDevice.address) {
                        newNode.name = node.name
                    }
                } addFail: {[weak self] addDevice, error in
                    print("添加失败")
                    
                } addFinish: {[weak self] successList, failList in
//                    guard let self = self else { return }
        //            self.addSuccessNodes.append(contentsOf: successNodes)
                }
                
                
            }
            
        } scanFinish: { list in
            
        }

        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        MeshAPI.stopScanRecoverDevices()
    }


}
