//
//  SpaceNewCreationProcessController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/4/17.
//

import UIKit
import NordicSigMeshSDK

class SpaceNewCreationProcessController: UIViewController {

    private var imageView: UIImageView!
    private var createMoreBtn: UIButton!
    private var createOtherBtn: UIButton!
    private var guidanceBtn: UIButton!
    
    let space: SpaceData
    var options: Options
    /// 是否进行下一步，非手动关闭
    private var isNext = false
    
    init(space: SpaceData, options: Options) {
        self.space = space
        self.options = options
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "guidance_process".localizedString
        view.backgroundColor = Background_Color
        
        navigationController?.setNavigationBarBackgroundColor(color: .clear)
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(back))
        
        setupUI()
        
        updateUI()
    }
    
    deinit {
        if !isNext && space.isConfiguring {
            space.isConfiguring = false
        }
    }
    
    @objc private func back() {
        if parent != nil {
            dismiss(animated: true)
        }else {
            navigationController?.popViewController(animated: true)
        }
    }
    
    private func updateUI() {
        
        switch options {
        case .scene:
            createMoreBtn.setTitle("create_more_scenes".localizedString, for: .normal)
            createOtherBtn.setTitle("create_schedule".localizedString, for: .normal)
        case .schedule:
            createMoreBtn.setTitle("create_more_schedules".localizedString, for: .normal)
            createOtherBtn.setTitle("create_virtual_switchs".localizedString, for: .normal)
        case .switch:
            createMoreBtn.setTitle("create_more_switchs".localizedString, for: .normal)
            createOtherBtn.setTitle("Finish".localizedString, for: .normal)
        }
    }
    
    /// 创建场景/日程
    @objc private func createMoreBtnAction() {
        
        switch options {
        case .scene:
            guard MeshNetworkManager.instance.scenes.count < 16 else {
                XWHUDManager.showTipHUD("scenes_overrun_message".localizedString, isLineFeed: true)
                return
            }
            space.isConfiguring = true
            let vc = SceneAddViewController(space: space)
            if isIPad {
                vc.preferredContentSize = iPadPreferredContentSize
            }
            present(NavigationViewController(rootViewController: vc), animated: true)
        case .schedule:
            guard MeshNetworkManager.instance.schedules.count < 16 else {
                XWHUDManager.showTipHUD("schedules_overrun_message".localizedString, isLineFeed: true)
                return
            }
            space.isConfiguring = true
            let vc = ScheduleAddViewController(space: space)
            if isIPad {
                vc.preferredContentSize = iPadPreferredContentSize
            }
            present(NavigationViewController(rootViewController: vc), animated: true)
            
            NotificationCenter.default.post(name: .init(spaceMenuIndexChangeNotificaitonName), object: 3)
        case .switch:
            
            guard MeshNetworkManager.instance.switchs.count < 16 else {
                SRAlertView(title: "notification".localizedString, message: "switchs_overrun_message".localizedString, actions: [SRAlertAction(title: "GOT_IT".localizedString)]).show()
                return
            }
            space.isConfiguring = true
            let vc = DeviceSwitchViewController(space: self.space, switchData: nil)
            if isIPad {
                vc.preferredContentSize = iPadPreferredContentSize
            }
            present(NavigationViewController(rootViewController: vc), animated: true)
        }
        
    }
    
    /// 创建其它
    @objc private func createOtherBtnAction() {
        
        switch options {
        case .scene:
//            createMoreBtnAction()
            space.isConfiguring = true
            self.dismiss(animated: false)
            
            isNext = true
            
            let vc = ScheduleAddViewController(space: space)
//            UIViewController.getVisibleVc()?.presentingViewController?.present(NavigationViewController(rootViewController: vc), animated: true)
            NotificationCenter.default.post(name: .init(spaceModalViewControllerNotificaitonName), object: NavigationViewController(rootViewController: vc))
            NotificationCenter.default.post(name: .init(spaceMenuIndexChangeNotificaitonName), object: 3)
        case .schedule:
//            XWHUDManager.showTipHUD("create_virtual_switch_message".localizedString, isLineFeed: true)
            
            space.isConfiguring = true
            self.dismiss(animated: false)
            isNext = true
            
            guard MeshNetworkManager.instance.switchs.count < 16 else {
                SRAlertView(title: "notification".localizedString, message: "switchs_overrun_message".localizedString, actions: [SRAlertAction(title: "GOT_IT".localizedString)]).show()
                return
            }
            let vc = DeviceSwitchViewController(space: self.space, switchData: nil)
//            UIViewController.getVisibleVc()?.presentingViewController?.present(NavigationViewController(rootViewController: vc), animated: true)
            NotificationCenter.default.post(name: .init(spaceModalViewControllerNotificaitonName), object: NavigationViewController(rootViewController: vc))
            NotificationCenter.default.post(name: .init(spaceMenuIndexChangeNotificaitonName), object: 0)
            
        case .switch:
            back()
        }
        updateUI()
        
    }
    
    /// 引导帮助
    @objc private func guidanceBtnAction() {
        
        ConfigurationFlowGuidanceView().show()
    }
    
    private func setupUI() {
        
        imageView = UIImageView(image: UIImage(named: "guidance_create"))
        view.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo((navigationController?.navigationBar.height ?? 0) + SCRYFit(100))
        }
        
        createMoreBtn = UIButton(title: "create_more_scenes".localizedString, titleSize: 16, titleWeight: .light, titleColor: .white, target: self, action: #selector(createMoreBtnAction))
        createMoreBtn.layer.cornerRadius = SCRYFrom(10)
        createMoreBtn.backgroundColor = Bar_Color
        view.addSubview(createMoreBtn)
        createMoreBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.width.equalTo(SCRXFrom(216))
            make.height.equalTo(SCRYFrom(44))
            make.top.equalTo(imageView.snp.bottom).offset(SCRYFit(44))
        }
        
        createOtherBtn = UIButton(title: "create_switch".localizedString, titleSize: 16, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(createOtherBtnAction))
        createOtherBtn.layer.cornerRadius = SCRYFrom(10)
        createOtherBtn.layer.borderColor = Bar_Color.cgColor
        createOtherBtn.layer.borderWidth = 0.6
        createOtherBtn.backgroundColor = .white
        view.addSubview(createOtherBtn)
        createOtherBtn.snp.makeConstraints { make in
            make.centerX.width.height.equalTo(createMoreBtn)
            make.top.equalTo(createMoreBtn.snp.bottom).offset(SCRYFit(15))
        }
        
        guidanceBtn = UIButton(title: "configuration_flow_guidance".localizedString, titleSize: 15, titleWeight: .light, titleColor: SubText_Color, normalImageName: "help", target: self, action: #selector(guidanceBtnAction))
        view.addSubview(guidanceBtn)
        guidanceBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(createOtherBtn.snp.bottom).offset(SCRYFit(12))
        }
        
    }


}

extension SpaceNewCreationProcessController {
    
    enum Options {
        case scene
        case schedule
        case `switch`
    }
    
}
