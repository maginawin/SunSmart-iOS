//
//  GroupPathSequenceDeviceAddStepView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/21.
//

import UIKit

class GroupPathSequenceDeviceAddStepView: UIView {

    struct StepItem {
        let imageName: String
        let title: String
        let textColor: UIColor
    }
    
    let stackView = UIStackView()
    
    private var stepViews: [StepFunctionView] = []
    private var lineViews: [UIView] = []
    
    var lineWidth: CGFloat = SCRXFrom(40)
    
    var steps: [StepItem] = [] {
        didSet {
            buildSteps()
        }
    }

    init(frame: CGRect = .zero, steps: [StepItem]) {
        super.init(frame: frame)
        self.steps = steps
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(10)

        stackView.axis = .horizontal
        stackView.alignment = .top
        stackView.distribution = .fillEqually
        stackView.spacing = SCRXFrom(5)
        
        addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(14))
            make.right.equalTo(SCRXFrom(-14))
//            make.trailing.equalToSuperview().offset(-20)
            make.top.bottom.equalToSuperview()
        }

        buildSteps()
    }

    private func buildSteps() {
        
        stepViews.forEach { $0.removeFromSuperview() }
        lineViews.forEach { $0.removeFromSuperview() }
        
        stepViews.removeAll()
        lineViews.removeAll()
        
        for step in steps {
            let view = StepFunctionView(
                imageName: step.imageName,
                title: step.title,
                titleColor: step.textColor
            )
            stackView.addArrangedSubview(view)
            stepViews.append(view)
        }
        
//        layoutIfNeeded()
        addLines()
    }

    private func addLines() {

        guard stepViews.count > 1 else { return }

        for i in 0..<(stepViews.count - 1) {

            let line = UIView()
            line.backgroundColor = AssistText_Color
            addSubview(line)
            lineViews.append(line)

            let left = stepViews[i]
//            let right = stepViews[i + 1]

            line.snp.makeConstraints { make in
                make.centerY.equalTo(left.imageView.snp.centerY)
                make.width.equalTo(lineWidth)
                make.centerX.equalTo(left.snp.right)
//                make.left.equalTo(left.snp.right).offset(6)
//                make.right.equalTo(right.snp.left).offset(-6)
                make.height.equalTo(1)
            }
        }
    }
}

class StepFunctionView: UIView {

    let imageView = UIImageView()
    private let titleLabel = UILabel()

    init(imageName: String, title: String, titleColor: UIColor) {
        super.init(frame: .zero)

        snp.makeConstraints { make in
            make.width.lessThanOrEqualTo(SCRXFrom(107))
        }
        
        imageView.image = UIImage(named: imageName)
        addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.centerX.top.equalToSuperview()
            make.width.height.equalTo(20)
        }

        titleLabel.text = title
        titleLabel.textColor = titleColor
        titleLabel.font = .systemFont(ofSize: 12, weight: .light)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(imageView.snp.bottom).offset(SCRYFrom(8))
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
