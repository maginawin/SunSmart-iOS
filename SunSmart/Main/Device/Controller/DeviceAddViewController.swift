//
//  DeviceAddViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/28.
//

import UIKit
import NordicSigMeshSDK
import CoreBluetooth
import SwiftyJSON

/// 添加设备到目标
enum AddDeviceToTarget {
    

    var name: String {
        switch self {
        case .space(let space):
            return space.name
        case .group(let group):
            return group.name
        case .dongle(let dongle):
            return dongle.name
        }
    }
    
    /// 添加到空间
    case space(_ space: SpaceData)
    /// 添加到组
    case group(_ group: Group)
    /// 添加到dongle
    case dongle(_ dongle: DeviceDongleData)
}

/// 设备添加页面状态
enum DeviceAddState {
    /// 无状态
    case none
    /// 扫描设备中
    case scanning
    /// identify中
    case identifying
    /// 添加设备中
    case adding
    /// 设备添加完成
    case addFineshed
}

class DeviceAddViewController: WMPageController {
    
    //从火警那边进来添加设备v1.5
    var isEmerFireAlarm: Bool = false
    
    private var navigationBackBtn: UIButton!
    
    private var helpBtn: UIButton!
    /// header
    private var scanAnimationView: UIImageView!
    private var segmentedControl: CustomSegmentedControl!
    
    private let vcTitles: [String] = ["classic_mode".localizedString, "professional_mode".localizedString]
    
    private let menuHeight: CGFloat = isIPad ? SCRYFrom(40) : SCRYFrom(32)
    
    /// 所属空间
    let space: SpaceData
    /// 设备添加完成回调
    var deviceAddCallback: (([Node])->Void)?
    /// 添加成功的节点
    private var addSuccessNodes: [Node] = []
    
    /// 外部传入指定添加该到group
    var appointGroup: Group?
    /// 外部传入指定dognle设备绑定该到dognle数据
    var forceBindToDongle: DeviceDongleData?
    /// 是否添加设备中
    var addingDevice: Bool = false
    
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
            title = "add_device".localizedString
        }
        view.backgroundColor = Background_Color
        self.isModalInPresentation = true
        
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
        if navigationController?.viewControllers.count ?? 0 > 1 {
            navigationController?.popViewController(animated: true)
        }else {
            dismiss(animated: true)
        }
    }
    
    deinit {
        if self.addSuccessNodes.count > 0 {
            // 找出未命名的设备
//            let unnamedNodes = addSuccessNodes.filter({ $0.deviceType != .gateway && !($0.name?.contains("ID") ?? true) })
//            if unnamedNodes.count > 0 {
//                unnamedNodes.forEach({
//                    $0.name = MeshNetworkManager.instance.getNextNodeName()
//                    $0.save()
//                })
//                //                    _ = MeshNetworkManager.instance.save()
//            }
            self.deviceAddCallback?(self.addSuccessNodes)
        }
    }
    
    // MARK: - Scan
    
    func startScan() {
        
        scanAnimationView.layer.removeAnimation(forKey: "scan")
        scanAnimationView.isHidden = false
        scanAnimationView.layer.addRotationAnimation(duration: 1.5, repeatCount: .max, animationKey: "scan")
    }
    
    func stopScan() {
        scanAnimationView.isHidden = true
        scanAnimationView.layer.removeAnimation(forKey: "scan")
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
        
        scanAnimationView = UIImageView(image: UIImage(named: "loading"))
        scanAnimationView.isHidden = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: scanAnimationView)
        
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
    
    private func updateDeviceAddingUIState() {
        segmentedControl.isUserInteractionEnabled = !self.addingDevice
        navigationBackBtn.isHidden = self.addingDevice
        navigationController?.interactivePopGestureRecognizer?.isEnabled = !self.addingDevice
    }
    
}

extension DeviceAddViewController {
    
    override func numbersOfChildControllers(in pageController: WMPageController) -> Int {
        return vcTitles.count
    }
    
    override func pageController(_ pageController: WMPageController, viewControllerAt index: Int) -> UIViewController {
        switch index {
        case 0:
            let vc = DeviceAddClassicModeController(space: space)
            vc.appointGroup = appointGroup
            vc.forceBindToDongle = forceBindToDongle
            vc.deviceAddCallback = {[weak self] nodes in
                guard let self = self else { return }
                self.addSuccessNodes.append(contentsOf: nodes)
            }
            vc.deviceStateCallback = {[weak self] adding in
                guard let self = self else { return }
                self.addingDevice = adding
                self.updateDeviceAddingUIState()
            }
            return vc
        case 1:
            let vc = DeviceAddProfessionalModeController(space: space)
            vc.appointGroup = appointGroup
            vc.forceBindToDongle = forceBindToDongle
            vc.deviceAddCallback = {[weak self] nodes in
                guard let self = self else { return }
                self.addSuccessNodes.append(contentsOf: nodes)
            }
            vc.deviceStateCallback = {[weak self] adding in
                guard let self = self else { return }
                self.addingDevice = adding
                self.updateDeviceAddingUIState()
            }
            return vc
        default:
            return UIViewController()
        }
    }
    
    override func pageController(_ pageController: WMPageController, preferredFrameForContentView contentView: WMScrollView) -> CGRect {
        let y = view.safeAreaInsets.top + SCRYFrom(16) + menuHeight
        return CGRect(x: 0, y: y, width: view.width, height: view.height - y)
    }
    
    override func pageController(_ pageController: WMPageController, preferredFrameFor menuView: WMMenuView) -> CGRect {
        return CGRect(x: 0, y: view.safeAreaInsets.top + SCRYFrom(16), width: view.width, height: menuHeight)
    }
    
    override func menuView(_ menu: WMMenuView!, shouldSelesctedIndex index: Int) -> Bool {
        return !addingDevice
//        return index < 3
    }
    
    override func menuView(_ menu: WMMenuView!, titleAt index: Int) -> String! {
        return ""
    }
    
    
    
//    override func pageController(_ pageController: WMPageController, didEnter viewController: UIViewController, withInfo info: [AnyHashable : Any]) {
//        segmentedControl?.selectedIndex = Int(self.selectIndex)
//    }
    
}

extension DeviceAddViewController: CustomSegmentedControlDelegate,UIAdaptivePresentationControllerDelegate {
    
    /// 分段控制器切换item回调
    /// - Parameters:
    ///   - segmentedControl: 分段控制器
    ///   - index: 点击索引
    func segmentedControl(_ segmentedControl: CustomSegmentedControl, didSelectedItem index: Int) {
        self.selectIndex = Int32(index)
        stopScan()
        //从火警那边进来添加设备v1.5
        if(isEmerFireAlarm){
            cct(index: index)
        }
    }
    //共用条件
    func cct(index: Int){
        if index == 1 {
            segmentedControl.selectedIndex = 0
            self.selectIndex = 0
            
            let vc = EmerFireAlarmAddProfessionalVC(space: space)
            vc.presentationController?.delegate = self
            present(vc, animated: true)
            return
        }

        segmentedControl.selectedIndex = 0
        self.selectIndex = 0
    }
    
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        segmentedControl.selectedIndex = 0
        selectIndex = 0
    }
    
}
