//
//  GatewayViewController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/6/17.
//

import UIKit

class GatewayViewController: UIViewController {

    private var tableView: UIView!
//    private var bottomView: DeviceBottomBtnView
    
    override func viewDidLoad() {
        super.viewDidLoad()

        navigationController?.setNavigationBarBackgroundColor(color: Background_Color)
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(close))
    }

    @objc private func close() {
        dismiss(animated: true)
    }
    
    

}
