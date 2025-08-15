//
//  DeviceForceResetDevicePageController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/8/14.
//

import UIKit
import NordicSigMeshSDK

class DeviceForceResetDevicePageController: WMPageController {

    private var navigationBackBtn: UIButton!
    
    private var helpBtn: UIButton!
    private var segmentedControl: CustomSegmentedControl!
    
    private let vcTitles: [String] = ["classic_mode".localizedString, "professional_mode".localizedString]
    
    /// 参数设置view
    private var parameterSettingsView :DeviceAddParameterSettingsView?
    private var parameterData: DeviceAddParameterData = .init(notificationEnable: true, volume: 50, vibrationEnable: true)
    
    /// 所属空间
    let space: SpaceData
    /// 设备重置完成回调
    var deviceResetCallback: (([Node])->Void)?
    /// 重置成功的节点
    private var resetSuccessNodes: [Node] = []

    init(space: SpaceData) {
        self.space = space
        super.init(nibName: nil, bundle: nil)
        
        self.scrollEnable = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if title == nil {
            title = "force_reset_the_device".localizedString
        }
        view.backgroundColor = Background_Color
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "device_add_setting")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(parameterSettings))
        
        setupUI()
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
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        helpBtn.isHidden = true
    }
    
    @objc private func backClick() {
        navigationController?.popViewController(animated: true)
    }
    
    @objc private func parameterSettings() {
        if parameterSettingsView == nil {
            parameterSettingsView = DeviceAddParameterSettingsView(frame: UIScreen.main.bounds, parameterData: self.parameterData)
            parameterSettingsView?.volumeChangedEndCallback = { volume in
                try? DeviceAudioManager.manager.startAudio(type: .deviceReset, volume: volume)
            }
            parameterSettingsView?.settingsCallback = {[weak self] data in
                guard let self = self else { return }
                self.parameterData = data
            }
        }
        parameterSettingsView?.show()
    }

    
    
    @objc private func helpBtnAction() {
        let vc = DeviceAddInstructionsController()
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
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.height.equalToSuperview()
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
        switch index {
        case 0:
            let vc = DeviceForceResetDeviceController()
            
//            vc.deviceAddCallback = {[weak self] nodes in
//                guard let self = self else { return }
//                self.addSuccessNodes.append(contentsOf: nodes)
//            }
//            vc.deviceStateCallback = {[weak self] adding in
//                guard let self = self else { return }
//                self.addingDevice = adding
//                self.updateDeviceAddingUIState()
//            }
            return vc
        case 1:
            let vc = DeviceAddProfessionalModeController(space: space)
//            vc.deviceAddCallback = {[weak self] nodes in
//                guard let self = self else { return }
//                self.resetSuccessNodes.append(contentsOf: nodes)
//            }
//            vc.deviceStateCallback = {[weak self] adding in
//                guard let self = self else { return }
//                self.addingDevice = adding
//                self.updateDeviceAddingUIState()
//            }
            return vc
        default:
            return UIViewController()
        }
    }
    
    override func pageController(_ pageController: WMPageController, preferredFrameForContentView contentView: WMScrollView) -> CGRect {
        let y = view.safeAreaInsets.top + SCRYFrom(32 + 16)
        return CGRect(x: 0, y: y, width: view.width, height: view.height - y)
    }
    
    override func pageController(_ pageController: WMPageController, preferredFrameFor menuView: WMMenuView) -> CGRect {
        return CGRect(x: 0, y: view.safeAreaInsets.top + SCRYFrom(16), width: view.width, height: SCRYFrom(32))
    }
    
//    override func menuView(_ menu: WMMenuView!, shouldSelesctedIndex index: Int) -> Bool {
//        return !addingDevice
//        return index < 3
//    }
    
    override func menuView(_ menu: WMMenuView!, titleAt index: Int) -> String! {
        return ""
    }
    
}

extension DeviceForceResetDevicePageController: CustomSegmentedControlDelegate {
    
    /// 分段控制器切换item回调
    /// - Parameters:
    ///   - segmentedControl: 分段控制器
    ///   - index: 点击索引
    func segmentedControl(_ segmentedControl: CustomSegmentedControl, didSelectedItem index: Int) {
        self.selectIndex = Int32(index)
    }
    
}
