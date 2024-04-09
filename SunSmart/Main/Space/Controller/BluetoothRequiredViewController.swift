//
//  BluetoothRequiredViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/10/19.
//

import UIKit
import CoreBluetooth

class BluetoothRequiredViewController: UIViewController {

    /// 蓝牙管理中心
//    private var cbCentralManager : CBCentralManager!
    
    private var navigationBar: UIView!
    private var backBtn: UIButton!
    
    private var isShowAlert: Bool = false
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Background_Color
        
        showBluetoothRequiredUI()
        
//        cbCentralManager = CBCentralManager(delegate: nil, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: true])
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(backItemClick))
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        
        showAlertView()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        if isShowAlert {
            SRAlertView.hide()
        }
    }
    
    @objc private func backItemClick() {
        navigationController?.popToViewController(vcClass: SiteViewController.classForCoder())
    }
    
    private func showBluetoothRequiredUI() {
        
        navigationBar = UIView()
        navigationBar.backgroundColor = .white
        view.addSubview(navigationBar)
        navigationBar.snp.makeConstraints { make in
            make.left.top.right.equalToSuperview()
            make.height.equalTo(kNavigationHeight)
        }
        
        
        view.showEmptyDataView(imageName: "bluetooth_required", title: "Bluetooth required", tipText: "Turn on bluetooth to use the app.")
        if let emptyView = view.emptyView {
            emptyView.titleLabel.font = Font_Medium_Size(SCRYFrom(16))
            emptyView.titleLabel.textColor = TextBlack_Color
            emptyView.titleLabel.snp.remakeConstraints { make in
                make.top.left.right.equalToSuperview()
            }
            emptyView.imageView.snp.remakeConstraints { make in
                make.centerX.equalToSuperview()
                make.top.equalTo(emptyView.titleLabel.snp.bottom).offset(SCRYFrom(40))
            }
            emptyView.tipLabel.snp.remakeConstraints { make in
                make.left.right.bottom.equalToSuperview()
                make.top.equalTo(emptyView.imageView.snp.bottom).offset(SCRYFrom(2))
            }
        }
    }
    
    private func showAlertView() {
        
        isShowAlert = true
        let alertView = SRAlertView(title: "bluetooth_required_title".localizedString, message: "bluetooth_required_message".localizedString, actions: [SRAlertAction(title: "settings".localizedString, titleColor: RGB(61, 110, 246), titleFont: FONTS(SCRYFrom(15)), actionHandler: {[weak self] _ in
            self?.isShowAlert = false
            if let openUrl = URL(string: "App-Prefs:root=Bluetooth") {
                UIApplication.shared.open(openUrl)
            }
        }), SRAlertAction(title: "close".localizedString, titleColor: RGB(61, 110, 246), titleFont: Font_Medium_Size(15), actionHandler: {[weak self] _ in
            self?.isShowAlert = false
        })])
        alertView.messageLabel.snp.updateConstraints { make in
            make.top.equalTo(alertView.titleLabel.snp.bottom).offset(SCRYFrom(8))
        }
        alertView.show()
//        let alertVc = UIAlertController(title: "bluetooth_required_title".localizedString, message: "bluetooth_required_message".localizedString, preferredStyle: .alert)
//        alertVc.addAction(UIAlertAction(title: "settings".localizedString, style: .cancel, handler: { _ in
//            if let openUrl = URL(string: "App-Prefs:root=Bluetooth") {
//                UIApplication.shared.open(openUrl)
//            }
//        }))
//        alertVc.addAction(UIAlertAction(title: "close".localizedString, style: .cancel))
//        present(alertVc, animated: true)
    }

}
