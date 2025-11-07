//
//  DeviceFlashlightBeastModeController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/10/17.
//

import UIKit
import NordicSigMeshSDK

class DeviceFlashlightBeastModeController: UIViewController {

    /// 导航栏按键
    private var navigationBackBtn: UIButton!
    private var settingsView: UIView!
    private var settingsBtn: UIButton!
    private var settingsTipView: UIView!
    /// 加载条
    private var loadingBar: GradientLoadingBar!
    /// 手电筒
    private var flaslightView: FlashlightSwingView!
    /// 提示
    private var noteLabel: UILabel!
    /// 底部view
    private var footerView: DeviceBottomBtnView!
    
    /// 参数设置view
    private var parameterSettingsView: DeviceAddParameterSettingsView?
    
    /// 无定向广播
    private let broadcaster = BluetoothBroadcaster()
    
    /// 广播时设备配置持续时长
    private let broadcasterDuration: UInt8 = 3
    
    /// 系统音量监听者
    private var systemVolumeObservation: NSKeyValueObservation?
    
    override func viewDidLoad() {
        super.viewDidLoad()
    
        title = "beast_mode".localizedString
        view.backgroundColor = Background_Color
        setupRightItem()
        setupUI()
        addObserver()
        
        startBroadcaster()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        SystemVolumeManager.shared.startObserveVolume()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        SystemVolumeManager.shared.stopObserveVolume()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopBroadcaster()
    }

    deinit {
        systemVolumeObservation = nil
    }
    
    private func addObserver() {
        
        systemVolumeObservation = SystemVolumeManager.shared.observe(\.currentVolume, options: [.new], changeHandler: {[weak self] _, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.settingsTipView.isHidden = SystemVolumeManager.shared.currentVolume >= DeviceSettingsParameterData.systemMinimumVolumeRequire
            }
        })
    }
    
    // MARK: - Broadcaster
    
    /// 开始无定向广播
    func startBroadcaster() {
       
        broadcaster.startBroadcasting(type: .flashlightFlashedReset(timeout: broadcasterDuration, periodMin: flashlightBeastModeParameterData.flashFrequency, periodMax: 500, delta: flashlightBeastModeParameterData.illuminationDelta), interval: 1)
    }
    
    /// 停止无定向广播
    private func stopBroadcaster() {
        broadcaster.stopBroadcasting()
    }
    
    @objc private func parameterSettings() {
        
        
        if parameterSettingsView == nil {
            parameterSettingsView = DeviceAddParameterSettingsView(frame: UIScreen.main.bounds, parameterData: flashlightBeastModeParameterData, showBrightness: false, showIllumination: true, illuminationTip: "illumination_fluctuation_range_reset_tip".localizedString, showFlashFrequency: true)
            parameterSettingsView?.volumeChangedEndCallback = { volume in
                try? DeviceAudioManager.manager.startAudio(type: .deviceReset, volume: volume)
            }
            parameterSettingsView?.settingsCallback = {[weak self] data in
                guard let self = self else { return }
                flashlightBeastModeParameterData = data
                // 正在发送扫描广播包中，修改广播包数据再发送
                if self.broadcaster.broadcasting {
                    self.startBroadcaster()
                }
            }
            parameterSettingsView?.helpActionCallback = {[weak self] in
                guard let self = self else { return }
//                self.parameterSettingsView?.dismiss()
                let vc = DeviceParameterSetupInstructionsController(mode: .reset(mode: .flashlight_beast))
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
    
    @objc private func finish() {
        navigationController?.popViewController(animated: true)
    }
    
    private func setupRightItem() {
        
        settingsView = UIView(frame: CGRect(x: 0, y: 0, width: 30, height: 30))
        settingsBtn = UIButton(normalImageName: "device_add_setting", target: self, action: #selector(parameterSettings))
        settingsBtn.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        settingsView.addSubview(settingsBtn)
        
        settingsTipView = UIView()
        settingsTipView.layer.cornerRadius = 2.5
        settingsTipView.backgroundColor = RGB(255, 167, 44)
        settingsTipView.isUserInteractionEnabled = false
        settingsTipView.isHidden = SystemVolumeManager.shared.currentVolume >= DeviceSettingsParameterData.systemMinimumVolumeRequire
        settingsBtn.addSubview(settingsTipView)
        settingsTipView.snp.makeConstraints { make in
            make.right.equalTo(-8.5)
            make.centerY.equalToSuperview().offset(0.5)
            make.width.height.equalTo(5)
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: settingsView)
    }
    
    private func setupUI() {
        
        loadingBar = GradientLoadingBar()
        view.addSubview(loadingBar)
        loadingBar.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(6))
            make.right.equalTo(SCRXFrom(-6))
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.height.equalTo(6)
        }
        
        flaslightView = FlashlightSwingView()
        view.addSubview(flaslightView)
        flaslightView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide).offset(SCRYFit(97))
        }
        
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineSpacing = 4
        noteLabel = UILabel(text: nil, textColor: ImportantText_Color, fontSize: 12)
        noteLabel.attributedText = NSAttributedString(string: "flashlight_beast_mode_reset_note".localizedString, attributes: [.paragraphStyle: style])
        noteLabel.numberOfLines = 0
        view.addSubview(noteLabel)
        noteLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(30))
            make.right.equalTo(SCRXFrom(-30))
            make.top.equalTo(flaslightView.snp.bottom).offset(SCRYFit(49))
        }

        
        footerView = DeviceBottomBtnView()
        footerView.createBtn.setTitle("finish".localizedString, for: .normal)
        footerView.createBtn.setTitleColor(Bar_Color, for: .normal)
        footerView.createBtn.addTarget(self, action: #selector(finish), for: .touchUpInside)
        footerView.showCreateUI()
        view.addSubview(footerView)
        footerView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(60) + kSafeAreaBottomHeight)
        }
        
    }

}
