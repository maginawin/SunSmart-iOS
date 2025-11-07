//
//  DeviceResetDeviceStepController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/10/15.
//

import UIKit

class DeviceResetDeviceStepController: UIViewController {

    private var scrollView: UIScrollView!
    private var contentView: UIView!
    
    private var imageView: UIImageView!
    
    private var resetStepViews: [DeviceForceResetStepView] = []
    
    /// 参数设置view
    private var parameterSettingsView :DeviceAddParameterSettingsView?
    
    /// 系统音量监听者
    private var systemVolumeObservation: NSKeyValueObservation?
    
    let resetMode: ResetMode
    
    init(resetMode: ResetMode) {
        self.resetMode = resetMode
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "force_reset_the_device".localizedString
        view.backgroundColor = Background_Color
        
        setupUI()
        addObserver()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        SystemVolumeManager.shared.startObserveVolume()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        SystemVolumeManager.shared.stopObserveVolume()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if self.scrollView.firstShowFlashScrollIndicators {
            self.scrollView.flashScrollIndicatorsIfNeeded()
        }
    }
    
    deinit {
        systemVolumeObservation = nil
    }
    
    private func addObserver() {
        
        systemVolumeObservation = SystemVolumeManager.shared.observe(\.currentVolume, options: [.new], changeHandler: {[weak self] _, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.updateStepUI()
            }
        })
    }
    
    private func updateStepUI() {
        resetStepViews.forEach { stepView in
            stepView.settingsTipView.isHidden = SystemVolumeManager.shared.currentVolume >= DeviceSettingsParameterData.systemMinimumVolumeRequire
        }
    }
    
    private func setupUI() {
        
        scrollView = UIScrollView()
//        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
        scrollView.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalToSuperview()
//            make.height.greaterThanOrEqualToSuperview()
        }
        
        let data = resetMode.data
        
        imageView = UIImageView(image: UIImage(named: data.imageName))
        contentView.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(isIPad ? 100 : 16))
            make.right.equalTo(SCRXFrom(isIPad ? -100 : -16))
            make.top.equalTo(SCRYFrom(22))
//            make.centerX.equalToSuperview().offset(SCRXFrom(15))
            make.height.equalTo(imageView.snp.width).multipliedBy(170 / 311.0)
        }
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.alignment = .center
        
        var lastStepView: DeviceForceResetStepView?
        data.infos.enumerated().forEach { (index, info) in
            
            let resetStepView = DeviceForceResetStepView()
            resetStepView.titleLabel.text = info.title
            resetStepView.noteLabel.attributedText = NSAttributedString(string: info.message, attributes: [.paragraphStyle: paragraphStyle])
            resetStepView.stepView.step1View.titleLabel.text = info.steps[0]
            resetStepView.stepView.step2View.titleLabel.text = info.steps[1]
            resetStepView.stepView.step3View.titleLabel.text = info.steps[2]
            resetStepView.parameterBtn.isHidden = !info.setParameters
            resetStepView.delegate = self
            contentView.addSubview(resetStepView)
            resetStepView.snp.makeConstraints { make in
                make.left.equalTo(SCRXFrom(14))
                make.right.equalTo(SCRXFrom(-14))
                if let lastStepView = lastStepView {
                    make.top.equalTo(lastStepView.snp.bottom).offset(SCRYFrom(16))
                }else {
                    make.top.equalTo(imageView.snp.bottom).offset(SCRYFrom(26))
                }
                make.height.greaterThanOrEqualTo(SCRYFrom(200))
                if index == data.infos.count - 1 {
                    make.bottom.equalTo(SCRYFrom(-22))
                }
            }
            resetStepViews.append(resetStepView)
            lastStepView = resetStepView
        }
        
    }

}

extension DeviceResetDeviceStepController: DeviceForceResetStepViewDelegate {
    
    /// 开始事件
    func resetStepViewStartAction(_ view: DeviceForceResetStepView) {
        switch resetMode {
        case .flashlight:
            guard let index = resetStepViews.firstIndex(of: view) else {
                return
            }
            // 安全模式
            if resetMode.data.infos[index].safeMode {
                let vc = DeviceResetDeviceSafeModeController(resetMode: .flashlight)
                navigationController?.pushViewController(vc, animated: true)
            }else { // 暴力模式
                let vc = DeviceFlashlightBeastModeController()
                navigationController?.pushViewController(vc, animated: true)
            }
        case .motion:
            let vc = DeviceResetDeviceSafeModeController(resetMode: .motion)
            navigationController?.pushViewController(vc, animated: true)
        case .meshNetwork:
            let vc = DeviceMeshNetworkResetController()
            navigationController?.pushViewController(vc, animated: true)
        }
    }
    
    /// 参数选择事件
    func resetStepViewSelectParameterAction(_ view: DeviceForceResetStepView) {
        guard let index = resetStepViews.firstIndex(of: view) else {
            return
        }
        
        var parameterData: DeviceSettingsParameterData = .default
        var showFlashFrequency: Bool = false
        var showIllumination: Bool = false
        switch self.resetMode {
        case .flashlight:
            // 安全模式
            if resetMode.data.infos[index].safeMode {
                parameterData = flashlightSafeModeParameterData
            }else {
                parameterData = flashlightBeastModeParameterData
                showFlashFrequency = true
            }
            showIllumination = true
        case .motion:
            parameterData = motionModeParameterData
        default:
            break
        }
        
        if parameterSettingsView == nil {
            parameterSettingsView = DeviceAddParameterSettingsView(frame: UIScreen.main.bounds, parameterData: parameterData, showBrightness: false, showIllumination: showIllumination, illuminationTip: "illumination_fluctuation_range_reset_tip".localizedString, showFlashFrequency: showFlashFrequency)
            parameterSettingsView?.volumeChangedEndCallback = { volume in
                try? DeviceAudioManager.manager.startAudio(type: .deviceReset, volume: volume)
            }
            parameterSettingsView?.settingsCallback = {[weak self] data in
                
                guard let self = self else { return }
                switch self.resetMode {
                case .flashlight:
                    if parameterSettingsView?.showFlashFrequency ?? false {
                        flashlightBeastModeParameterData = data
                    }else {
                        flashlightSafeModeParameterData = data
                    }
                case .motion:
                    motionModeParameterData = data
                default:
                    break
                }
            }
            parameterSettingsView?.helpActionCallback = {[weak self] in
                guard let self = self else { return }
//                self.parameterSettingsView?.dismiss()
                var mode: DeviceParameterSetupInstructionsController.Mode.ResetMode = .motion
                switch self.resetMode {
                case .flashlight:
                    if self.parameterSettingsView?.showFlashFrequency ?? false {
                        mode = .flashlight_beast
                    }else {
                        mode = .flashlight
                    }
                default:
                    break
                }
           
                let vc = DeviceParameterSetupInstructionsController(mode: .reset(mode: mode))
                if isIPad {
                    vc.preferredContentSize = iPadPreferredContentSize
                    self.parameterSettingsView?.dismiss()
                }
//                if self.presentingViewController == nil {
                    self.present(NavigationViewController(rootViewController: vc), animated: true)
//                }else {
//                    self.navigationController?.pushViewController(vc, animated: true)
//                }
            }
        }else {
            parameterSettingsView?.parameterData = parameterData
            parameterSettingsView?.showFlashFrequency = showFlashFrequency
            parameterSettingsView?.showIllumination = showIllumination
        }
        parameterSettingsView?.show()
    }
}

extension DeviceResetDeviceStepController {
    
    ///重置模式
    enum ResetMode {
        
        struct ModeInfo {
            let title: String?
            let message: String
            let steps: [String]
            let setParameters: Bool
            let safeMode: Bool
        }
        
        
        var data: (imageName: String, infos: [ModeInfo]) {
            switch self {
            case .flashlight:
                return ("device_reset_flashlight",
                        [ModeInfo(title: "safe_mode".localizedString, message: "reset_safe_mode_note".localizedString, steps: ["force_reset_step_1".localizedString, "flashlight_safe_mode_step_2".localizedString, "force_reset_step_3".localizedString], setParameters: true, safeMode: true),
                         ModeInfo(title: "beast_mode".localizedString, message: "flashlight_beast_mode_note".localizedString, steps: ["force_reset_step_1".localizedString, "flashlight_beast_mode_step_2".localizedString, "flashlight_beast_mode_step_3".localizedString], setParameters: true, safeMode: false)]
                )
            case .motion:
                return ("device_reset_motion", [
                    ModeInfo(title: "safe_mode".localizedString, message: "reset_safe_mode_note".localizedString, steps: ["force_reset_step_1".localizedString, "motion_reset_step_2".localizedString, "force_reset_step_3".localizedString], setParameters: true, safeMode: true),
                ])
            case .meshNetwork:
                return ("device_reset_network", [
                    ModeInfo(title: nil, message: "network_reset_note".localizedString, steps: ["force_reset_step_1".localizedString, "network_reset_step_2".localizedString, "force_reset_step_3".localizedString], setParameters: false, safeMode: true),
                ])
            }
        }
        
        /// 手电筒
        case flashlight
        /// 移动感应
        case motion
        /// mesh网络
        case meshNetwork
    }
    
    /// 手电筒模式
    enum FlashlightMode {
        /// 安全模式
        case safe
        /// 暴力模式
        case beast
    }
    
}
