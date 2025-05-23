//
//  GroupPathSequenceDeviceAddStepView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/21.
//

import UIKit

class GroupPathSequenceDeviceAddStepView: UIView {

    var step1View: StepFunctionView!
    var step2View: StepFunctionView!
    var step3View: StepFunctionView!
    private var step1LineView: UIView!
    private var step2LineView: UIView!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(10)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        step2View = StepFunctionView(imageName: "proximity_lighting_step2", title: "quick_add_step2".localizedString)
        addSubview(step2View)
        step2View.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(SCRXFrom(102))
//            make.height.greaterThanOrEqualTo(SCRYFrom(40))
        }
        
        step1View = StepFunctionView(imageName: "proximity_lighting_step1", title: "quick_add_step1".localizedString)
        addSubview(step1View)
        step1View.snp.makeConstraints { make in
            make.right.equalTo(step2View.snp.left).offset(SCRXFrom(-5))
            make.top.equalTo(step2View).offset(SCRYFrom(3))
            make.width.equalTo(step2View)
//            make.height.greaterThanOrEqualTo(SCRYFrom(40))
        }
        
        step1LineView = UIView()
        step1LineView.backgroundColor = AssistText_Color
        addSubview(step1LineView)
        step1LineView.snp.makeConstraints { make in
            make.width.equalTo(SCRXFrom(40))
            make.centerX.equalTo(step2View.snp.left).offset(SCRXFrom(-2.5))
            make.top.equalTo(step2View).offset(10)
            make.height.equalTo(1)
        }
        
        step3View = StepFunctionView(imageName: "proximity_lighting_step3", title: "quick_add_step3".localizedString)
        addSubview(step3View)
        step3View.snp.makeConstraints { make in
            make.left.equalTo(step2View.snp.right).offset(SCRXFrom(4))
            make.centerY.equalTo(step2View)
            make.width.equalTo(SCRXFrom(108))
//            make.width.lessThanOrEqualTo(SCRXFrom(102))
//            make.height.greaterThanOrEqualTo(SCRYFrom(40))
        }
        
        step2LineView = UIView()
        step2LineView.backgroundColor = AssistText_Color
        addSubview(step2LineView)
        step2LineView.snp.makeConstraints { make in
            make.centerX.equalTo(step2View.snp.right).offset(SCRXFrom(4))
            make.top.width.height.equalTo(step1LineView)
        }
        
    }
  
    
}

class StepFunctionView: UIView {
    
    var imageView: UIImageView!
    var titleLabel: UILabel!
    
    init(frame: CGRect = .zero, imageName: String, title: String) {
        super.init(frame: frame)
        
        imageView = UIImageView(image: UIImage(named: imageName))
        addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.centerX.top.equalToSuperview()
            make.width.height.equalTo(20)
        }
        
        titleLabel = UILabel(text: title, textColor: SubText_Color, fontSize: 12, fontWeight: .light, fit: false)
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.bottom.leading.trailing.equalToSuperview()
            make.top.equalTo(imageView.snp.bottom).offset(SCRYFrom(8))
        }
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
