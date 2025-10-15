//
//  ProfilePhasesTimePickerView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/3/1.
//

import UIKit

class ProfilePhasesTimePickerView: UIView {

    typealias TimePickerCallback = ((Int)->Void)
    
    private var shadeView: UIView!
    private var contentView: UIView!
    private var titleLabel: UILabel!
    private var lineView: UIView!
    private var nameLabel: UILabel!
    private var pickerView: UIPickerView!
    private var isAddPickerLine: Bool = false
    let times: [String]
    let pickerCallback: TimePickerCallback?
//    let selectIndex:
    
    init(title: String, name: String, times: [String], defalutSelectRow: Int = 0, pickerCallback: TimePickerCallback?) {
        
        self.times = times
        self.pickerCallback = pickerCallback
        super.init(frame: UIScreen.main.bounds)
        setupUI()
        titleLabel.text = title
        nameLabel.text = name
        if defalutSelectRow >= 0 && defalutSelectRow < times.count {
            pickerView.selectRow(defalutSelectRow, inComponent: 0, animated: false)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // 隐藏之前的选中框
        if let backgroundView = pickerView.subviews.last {
            backgroundView.backgroundColor = .clear
            
            // 添加分割线
            if !isAddPickerLine {
                isAddPickerLine = true
                let topLineView = UIView()
                topLineView.backgroundColor = RGB(218, 218, 218, 0.7)
                pickerView.addSubview(topLineView)
                topLineView.snp.makeConstraints { make in
                    make.left.right.equalTo(backgroundView)
//                    make.left.equalTo(30)
//                    make.right.equalTo(-30)
                    make.height.equalTo(1)
                    make.top.equalTo(backgroundView)
                }
                
                let bottomLineView = UIView()
                bottomLineView.backgroundColor = RGB(218, 218, 218, 0.7)
                pickerView.addSubview(bottomLineView)
                bottomLineView.snp.makeConstraints { make in
                    make.left.right.height.equalTo(topLineView)
                    make.bottom.equalTo(backgroundView)
                }
            }
            
        }
    }
    
    func show() {
        if self.superview == nil {
            self.tag = 100
            UIApplication.shared.keyWindow().addSubview(self)
//            layoutIfNeeded()
        }
        self.shadeView.alpha = 0
        self.contentView.alpha = 0
        UIView.animate(withDuration: 0.3) {
            self.shadeView.alpha = 1
            self.contentView.alpha = 1
        }
    }
    
    @objc private func shadeViewAction() {
        let row = pickerView.selectedRow(inComponent: 0)
        pickerCallback?(row)
        dismiss()
    }
    
    private func dismiss() {
        UIView.animate(withDuration: 0.3) {
            self.shadeView.alpha = 0
            self.contentView.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
        }

    }
    
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.backgroundColor = RGB(0, 0, 0, 0.3)
        shadeView.alpha = 0
        shadeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(shadeViewAction)))
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = 15
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-8))
            make.bottom.equalTo(SCRYFrom(-34))
            make.height.equalTo(SCRYFrom(240))
        }
        
        nameLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 15)
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalTo(SCRYFrom(23))
        }
        
        lineView = UIView()
        lineView.backgroundColor = RGB(220, 220, 220)
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(nameLabel.snp.right).offset(SCRXFrom(8))
            make.centerY.equalTo(nameLabel)
            make.width.equalTo(1)
            make.height.equalTo(SCRYFrom(10))
        }
        
        titleLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 15)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(lineView.snp.right).offset(SCRXFrom(8))
            make.centerY.equalTo(lineView)
        }
        
        pickerView = UIPickerView()
        pickerView.dataSource = self
        pickerView.delegate = self
        contentView.addSubview(pickerView)
        pickerView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(34))
            make.right.equalTo(SCRXFrom(-34))
            make.top.equalTo(SCRYFrom(60))
            make.bottom.equalTo(SCRYFrom(-24))
        }
    }
    
}

extension ProfilePhasesTimePickerView: UIPickerViewDataSource, UIPickerViewDelegate {
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return times.count
    }
    
    func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
        let titleLabel = view as? UILabel ?? UILabel()
        titleLabel.font = UIFont.systemFont(ofSize: 19, weight: .light)
        titleLabel.textColor = RGB(39, 37, 54)
        titleLabel.text = times[row]
//        titleLabel.width = pickerView.width / 3.0
        titleLabel.textAlignment = .center
        return titleLabel
    }
    
    func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
        return SCRYFrom(40)
    }
    
}
