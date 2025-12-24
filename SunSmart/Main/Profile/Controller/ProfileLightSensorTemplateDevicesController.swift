//
//  ProfileLightSensorTemplateDevicesController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/12/23.
//

import UIKit

class ProfileLightSensorTemplateDevicesController: UIViewController {

    private var sortBtn: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "applied_to_device".localizedString
        view.backgroundColor = Background_Color
        
        sortBtn = UIButton(title: "start".localizedString, titleSize: 14, titleColor: TextBlack_Color, normalImageName: "space_sort", target: self, action: #selector(sortBtnAction))
        sortBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: sortBtn)
    }
    
    @objc private func sortBtnAction() {
        
        
        
    }
    
    
    



}
