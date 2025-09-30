//
//  DeviceForceResetDevicePageController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/8/14.
//

import UIKit
import NordicSigMeshSDK
import AVFAudio

class DeviceForceResetDevicePageController: WMPageController {

    private var navigationBackBtn: UIButton!
    private var settingsView: UIView!
    private var settingsBtn: UIButton!
    private var settingsTipView: UIView!
    
    private var helpBtn: UIButton!
    private var segmentedControl: CustomSegmentedControl!
    
    private let vcTitles: [String] = ["based_on_flashlight".localizedString, "based_on_motion".localizedString]
    
    
    /// 参数设置view
    private var parameterSettingsView :DeviceAddParameterSettingsView?
    /// 是否操作设备中
    private var operatingDevice: Bool = false
    
    /// 设备重置完成回调
    var deviceResetCallback: (([Node])->Void)?
    /// 重置成功的设备
    private var resetSuccessDevices: [ProvisioningDevice] = []
    
    /// 系统音量监听者
    private var systemVolumeObservation: NSKeyValueObservation?

//    init(space: SpaceData) {
//        self.space = space
//        super.init(nibName: nil, bundle: nil)
//        
//        self.scrollEnable = false
//    }
    
//    required init?(coder: NSCoder) {
//        fatalError("init(coder:) has not been implemented")
//    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.scrollEnable = false
        
        if title == nil {
            title = "force_reset_the_device".localizedString
        }
        view.backgroundColor = Background_Color
        setupUI()
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: settingsView)
        
        addObserver()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if let navContentView = navigationController?.navigationBarContentView, let titleView = navigationController?.navigationBarTitleView {
            if helpBtn.superview == nil {
                navContentView.addSubview(helpBtn)
            }
            helpBtn.isHidden = false
            helpBtn.snp.makeConstraints { make in
                make.left.equalTo(titleView.snp.right).offset(SCRXFrom(4))
                make.centerY.equalToSuperview()
            }
        }
        MeshLibManager.manager.close()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        helpBtn.isHidden = true
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        MeshLibManager.manager.open()
    }
    
    deinit {
        systemVolumeObservation = nil
     
    }
    
    private func addObserver() {
        
        // 激活 AVAudioSession（否则监听可能无效）
        try? AVAudioSession.sharedInstance().setActive(true, options: [])

        systemVolumeObservation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new], changeHandler: {[weak self] _, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.settingsTipView.isHidden = AVAudioSession.sharedInstance().outputVolume >= DeviceSettingsParameterData.systemMinimumVolumeRequire
            }
        })
    }
    
    
    @objc private func backClick() {
        navigationController?.popViewController(animated: true)
    }
    
    @objc private func parameterSettings() {
        if parameterSettingsView == nil {
            parameterSettingsView = DeviceAddParameterSettingsView(frame: UIScreen.main.bounds, parameterData: deviceSettingsParameterData, showBrightness: false)
            parameterSettingsView?.volumeChangedEndCallback = { volume in
                try? DeviceAudioManager.manager.startAudio(type: .deviceReset, volume: volume)
            }
            parameterSettingsView?.settingsCallback = {[weak self] data in
                deviceSettingsParameterData = data
                // 正在发送扫描广播包中，修改广播包数据再发送
                if let vc = self?.currentViewController as? DeviceForceResetDeviceController, vc.state == .scaning {
                    vc.startBroadcaster()
                }
            }
            parameterSettingsView?.helpActionCallback = {[weak self] in
                guard let self = self else { return }
//                self.parameterSettingsView?.dismiss()
                let vc = DeviceParameterSetupInstructionsController(mode: .reset)
                if isIPad {
                    vc.preferredContentSize = iPadPreferredContentSize
                    self.parameterSettingsView?.dismiss()
                }
                if self.presentingViewController == nil {
                    self.present(NavigationViewController(rootViewController: vc), animated: true)
                }else {
                    self.navigationController?.pushViewController(vc, animated: true)
                }
            }
        }else {
            parameterSettingsView?.parameterData = deviceSettingsParameterData
        }
        parameterSettingsView?.show()
    }

    
    
    @objc private func helpBtnAction() {
        let vc = DeviceForceResetDeviceInstructionsController()
        if isIPad {
            vc.preferredContentSize = iPadPreferredContentSize
        }
        present(NavigationViewController(rootViewController: vc), animated: true)
    }

    private func setupUI() {
        
        navigationBackBtn = UIButton(normalImageName: "navigation_back", target: self, action: #selector(backClick))
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: navigationBackBtn)
        
        helpBtn = UIButton(normalImageName: "help", target: self, action: #selector(helpBtnAction))
        
        segmentedControl = CustomSegmentedControl(frame: .zero, titles: vcTitles)
        segmentedControl.margin = 0
        segmentedControl.cornerRadius = SCRYFrom(8)
        segmentedControl.titleFont = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
//        segmented.selectedIndex = 1
        segmentedControl.delegate = self
        menuView?.addSubview(segmentedControl)
//        CGRect(x: SCRXFrom(16), y: SCRYFrom(16) + kNavigationHeight, width: view.width - SCRXFrom(32), height: SCRYFrom(44))
        segmentedControl.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.left.equalTo(SCRXFrom(16)).priority(.low)
            make.right.equalTo(SCRXFrom(-16)).priority(.low)
            make.height.equalToSuperview()
        }
        
        settingsView = UIView(frame: CGRect(x: 0, y: 0, width: 30, height: 30))
        settingsBtn = UIButton(normalImageName: "device_add_setting", target: self, action: #selector(parameterSettings))
        settingsBtn.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        settingsView.addSubview(settingsBtn)
        
        settingsTipView = UIView()
        settingsTipView.layer.cornerRadius = 2.5
        settingsTipView.backgroundColor = RGB(255, 167, 44)
        settingsTipView.isUserInteractionEnabled = false
        settingsTipView.isHidden = AVAudioSession.sharedInstance().outputVolume >= DeviceSettingsParameterData.systemMinimumVolumeRequire
        settingsBtn.addSubview(settingsTipView)
        settingsTipView.snp.makeConstraints { make in
            make.right.equalTo(-8.5)
            make.centerY.equalToSuperview().offset(0.5)
            make.width.height.equalTo(5)
        }
        
    }
    
    private func updateDeviceResetingUIState() {
//        segmentedControl.isUserInteractionEnabled = !self.addingDevice
//        navigationBackBtn.isHidden = self.addingDevice
//        navigationController?.interactivePopGestureRecognizer?.isEnabled = !self.addingDevice
    }
    

}

extension DeviceForceResetDevicePageController {
    
    override func numbersOfChildControllers(in pageController: WMPageController) -> Int {
        return vcTitles.count
    }
    
    override func pageController(_ pageController: WMPageController, viewControllerAt index: Int) -> UIViewController {
        
        let vc = DeviceForceResetDeviceController(resetMode: index == 0 ? .flashlight : .motion)
        vc.delegate = self
        return vc
    }
    
    override func pageController(_ pageController: WMPageController, preferredFrameForContentView contentView: WMScrollView) -> CGRect {
        let y = view.safeAreaInsets.top + SCRYFrom(32 + 16)
        return CGRect(x: 0, y: y, width: view.width, height: view.height - y)
    }
    
    override func pageController(_ pageController: WMPageController, preferredFrameFor menuView: WMMenuView) -> CGRect {
        return CGRect(x: 0, y: view.safeAreaInsets.top + SCRYFrom(16), width: view.width, height: SCRYFrom(32))
    }
    
    override func menuView(_ menu: WMMenuView!, shouldSelesctedIndex index: Int) -> Bool {
        return !operatingDevice
    }
    
    override func menuView(_ menu: WMMenuView!, titleAt index: Int) -> String! {
        return ""
    }
    
}

extension DeviceForceResetDevicePageController: CustomSegmentedControlDelegate {
    
    /// 分段控制器是否可以点击item回调
    /// - Parameters:
    ///   - segmentedControl: 分段控制器
    ///   - index: 点击索引
    func segmentedControl(_ segmentedControl: CustomSegmentedControl, shouldSelesctedItem index: Int) -> Bool {
        return !operatingDevice
    }
    
    /// 分段控制器切换item回调
    /// - Parameters:
    ///   - segmentedControl: 分段控制器
    ///   - index: 点击索引
    func segmentedControl(_ segmentedControl: CustomSegmentedControl, didSelectedItem index: Int) {
        self.selectIndex = Int32(index)
        navigationBackBtn.isHidden = false
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }
    
}

extension DeviceForceResetDevicePageController: DeviceForceResetDeviceControllerDelegate {
    
    /// 发现设备
    func controller(_ controller: DeviceForceResetDeviceController, deviceDiscovered device: ProvisioningDevice) {
        // 播放声音
        if deviceSettingsParameterData.notificationEnable {
            try? DeviceAudioManager.manager.startAudio(type: .deviceReset, volume: deviceSettingsParameterData.volume)
        }
        if deviceSettingsParameterData.vibrationEnable {
            DeviceAudioManager.manager.vibration()
        }
    }
    
    /// 设备操作状态
    func controller(_ controller: DeviceForceResetDeviceController, deviceStateChanged deviceState: DeviceForceResetDeviceController.DeviceState) {
        
        operatingDevice = deviceState == .reseting || deviceState == .identifying
        
        if operatingDevice {
            navigationBackBtn.isHidden = true
            navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }else {
            navigationBackBtn.isHidden = false
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }
        
    }
    
    /// 设备重置成功
    func controller(_ controller: DeviceForceResetDeviceController, deviceResetFinish device: ProvisioningDevice) {
 
        if let meshNetwork = MeshNetworkManager.instance.meshNetwork, let node = meshNetwork.nodes.first(where: { $0.macAddress ==  device.macAddress }) {
            meshNetwork.remove(node: node)
            node.deleteExtension()
            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
        }
        if !resetSuccessDevices.contains(where: { $0.peripheral.identifier ==  device.peripheral.identifier }) {
            resetSuccessDevices.append(device)
        }
    }
     
}
