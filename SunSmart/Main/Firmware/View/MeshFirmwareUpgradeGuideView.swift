//
//  MeshFirmwareUpgradeGuideView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/11/4.
//

import UIKit

class MeshFirmwareUpgradeGuideView: UIView {

    private var shadeView: UIView!
    private var contentView: UIView!
    private var titleView: UIView!
    private var titleLabel: UILabel!
    private var messageLabel: UILabel!
    
    
}

class MeshFirmwareUpgradeGuideStepView: UIView {
    
    /// 流程
    enum Step {
        
//        var data: (index: Int, title: String, imageName: String, showArrow: Bool) {
//            switch self {
//            case .selectDistributor:
//                return (1, "")
//            case .selectDevices:
//                <#code#>
//            case .waiting:
//                <#code#>
//            }
//        }
         
        
        /// 选择分发者
    case selectDistributor
        /// 选择升级设备
    case selectDevices
        /// 等待
    case waiting
    }
    
    
    var stepLabel: UILabel!
    var titleLabel: UILabel!
    var guideImageView: UIImageView!
    var arrowImageView: UIImageView!
    
//    init(step: Step) {
//        
//    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    
    
}
