//
//  SpaceFunctionFooterView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/27.
//

import UIKit

protocol SpaceFunctionFooterViewDelegate: AnyObject {
    
    /// 点击排序回调
    func functionDidClickSort(view: SpaceFunctionFooterView)
    
    /// 点击添加回调
    func functionDidClickAdd(view: SpaceFunctionFooterView)
    
    /// 编辑/取消编辑状态修改  editing：是否正在编辑
    func function(view: SpaceFunctionFooterView, editStateChanged editing: Bool)
    
    /// 点击删除回调
    func functionDidClickDelete(view: SpaceFunctionFooterView)
    
    /// 点击修复
    func functionDidClickSync(view: SpaceFunctionFooterView)
    
    /// 进入测试删除
    func functionEnterIntoTestDelete(view: SpaceFunctionFooterView)
}

extension SpaceFunctionFooterViewDelegate {
    
    /// 点击排序回调
    func functionDidClickSort(view: SpaceFunctionFooterView) {
        
    }
    
    /// 点击添加回调
    func functionDidClickAdd(view: SpaceFunctionFooterView) {
        
    }
    
    /// 编辑/取消编辑状态修改  editing：是否正在编辑
    func function(view: SpaceFunctionFooterView, editStateChanged editing: Bool) {
        
    }
    
    /// 点击删除回调
    func functionDidClickDelete(view: SpaceFunctionFooterView) {
        
    }
    
    /// 点击修复
    func functionDidClickSync(view: SpaceFunctionFooterView) {
        
    }
    
    /// 进入测试删除
    func functionEnterIntoTestDelete(view: SpaceFunctionFooterView) {
        
    }

}


class SpaceFunctionFooterView: UIView {

    var countBtn: UIButton!
    var switchCountBtn: UIButton!
    var sortBtn: UIButton!
    var editBtn: UIButton!
    var addBtn: UIButton!
    var syncBtn: UIButton!
    
    var cancelBtn: UIButton!
    var lineView: UIView!
    var deleteBtn: UIButton!
    /// 是否启用测试删除
    var enableTestDelete: Bool = false
    
    private weak var promptLabel: UILabel?
    
    private var longPressTestBtn: UIButton!
    
    /// 是否正在编辑
    var isEditing: Bool = false {
        didSet {
            updateUI()
        }
    }
    
    weak var delegate: SpaceFunctionFooterViewDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    /// 排序
    @objc private func sortBtnClick() {
        delegate?.functionDidClickSort(view: self)
    }
    
    /// 编辑
    @objc private func editBtnClick() {
        
        isEditing = true
        delegate?.function(view: self, editStateChanged: true)
    }
    
    /// 添加
    @objc private func addBtnClick() {
        delegate?.functionDidClickAdd(view: self)
    }
    
    /// 取消
    @objc private func cancelBtnClick() {
            
        isEditing = false
        delegate?.function(view: self, editStateChanged: false)
    }
    
    /// 删除
    @objc private func deleteBtnClick() {
        delegate?.functionDidClickDelete(view: self)
    }
    
    /// 同步
    @objc private func syncBtnClick() {
        delegate?.functionDidClickSync(view: self)
    }
    
    /// 删除（test）
    @objc private func deleteBtnLongPress(sender: UILongPressGestureRecognizer) {
        if sender.state == .began, enableTestDelete {
            // 输入密码
            let alertView = SRAlertView(title: "force_reset_the_device".localizedString, message: "force_reset_the_device_message".localizedString, inputText: nil, inputFieldStyle: .init(keyboardType: .numberPad, minInputLength: 4, maxInputLength: 4, borderColor: Bar_Color, textAlignment: .center, showClear: false), showPrompt: false, showClose: true, textValueChangedBack: {[weak self] password, _ in
                guard let self = self else { return nil }
                guard password.count >= 4 else {
                    self.promptLabel?.isHidden = true
                    SRAlertView.getCurrentAlertView()?.textField.layer.borderColor = Bar_Color.cgColor
                    return nil
                }
                guard password == "1314" else {
                    self.promptLabel?.isHidden = false
                    SRAlertView.getCurrentAlertView()?.textField.layer.borderColor = Red_Color.cgColor
                    return nil
                }
                SRAlertView.hide()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {[weak self] in
                    guard let self = self else { return }
                    self.delegate?.functionEnterIntoTestDelete(view: self)
                })
                return nil
            }, inputDoneBack: nil)
            
            alertView.hLineView.snp.remakeConstraints { make in
                make.left.right.equalTo(0)
                make.height.equalTo(0.5)
                make.top.equalTo(alertView.textField.snp.bottom).offset(SCRYFrom(54))
            }
            
            let promptLabel = UILabel(text: "incorrect_password".localizedString, textColor: Red_Color, fontSize: 14, fontWeight: .light)
            promptLabel.isHidden = true
            alertView.contentView.addSubview(promptLabel)
            self.promptLabel = promptLabel
            promptLabel.snp.makeConstraints { make in
                make.top.equalTo(alertView.textField.snp.bottom).offset(SCRYFrom(8))
                make.centerX.equalToSuperview()
                make.height.equalTo(SCRYFrom(22))
            }
            alertView.show()
            
        }
    }
    
    
    /// 更新UI
    private func updateUI() {
        if isEditing {
            
            cancelBtn.isHidden = false
            lineView.isHidden = false
            deleteBtn.isHidden = false
            countBtn.isHidden = true
            editBtn.isHidden = true
            addBtn.isHidden = true
            sortBtn.isHidden = true
            syncBtn.isHidden = true
            longPressTestBtn.isHidden = true
//            switchCountBtn.isHidden = true
        }else {
            cancelBtn.isHidden = true
            lineView.isHidden = true
            deleteBtn.isHidden = true
            countBtn.isHidden = false
            editBtn.isHidden = false
            addBtn.isHidden = false
            sortBtn.isHidden = false
            longPressTestBtn.isHidden = false
//            switchCountBtn.isHidden = false
        }
    }
    
    private func setupUI() {
        
        countBtn = UIButton(title: "25/100", titleSize: 12, titleColor: TextBlack_Color, normalImageName: "space_device_count")
        countBtn.setImagePosition(position: .left, spacing: SCRXFrom(2))
        countBtn.isUserInteractionEnabled = false
        addSubview(countBtn)
        countBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalTo(SCRYFrom(5))
        }
        
        switchCountBtn = UIButton(title: "0/16", titleSize: 12, titleColor: TextBlack_Color, normalImageName: "space_switch_count")
        switchCountBtn.setImagePosition(position: .left, spacing: SCRXFrom(2))
        switchCountBtn.isUserInteractionEnabled = false
        switchCountBtn.isHidden = true
        addSubview(switchCountBtn)
        switchCountBtn.snp.makeConstraints { make in
            make.left.equalTo(countBtn.snp.right).offset(SCRXFrom(20))
            make.centerY.equalTo(countBtn)
        }
        
        cancelBtn = UIButton(title: "cancel".localizedString, titleSize: 17, titleWeight: .light, titleColor: TextBlack_Color, target: self, action: #selector(cancelBtnClick))
        cancelBtn.isHidden = true
        addSubview(cancelBtn)
        cancelBtn.snp.makeConstraints { make in
//            make.left.equalTo(SCRXFrom(34))
            make.centerX.equalTo(self).multipliedBy(0.5)
            make.top.equalTo(SCRYFrom(14))
            make.width.equalTo(SCRXFrom(120))
            make.height.equalTo(SCRYFrom(30))
        }
        
        lineView = UIView()
        lineView.isHidden = true
        lineView.backgroundColor = Line_Color
        addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalTo(cancelBtn)
            make.width.equalTo(1)
            make.height.equalTo(SCRYFrom(40))
        }
        
        deleteBtn = UIButton(title: "DELETE".localizedString, titleSize: 17, titleWeight: .light, titleColor: Red_Color, target: self, action: #selector(deleteBtnClick))
//        deleteBtn.titleLabel?.font = Font_Medium_Size(SCRYFrom(17))
        deleteBtn.setTitleColor(RGB(147, 146, 154), for: .disabled)
        deleteBtn.isHidden = true
        addSubview(deleteBtn)
        deleteBtn.snp.makeConstraints { make in
//            make.left.equalTo(lineView.snp.right).offset(SCRXFrom(34))
            make.centerX.equalTo(self).multipliedBy(1.5)
            make.width.height.centerY.equalTo(cancelBtn)
        }
        
        
        addBtn = UIButton(normalImageName: "space_add", target: self, action: #selector(addBtnClick))
        addSubview(addBtn)
        addBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-30))
            make.centerY.equalTo(countBtn)
        }
        
        longPressTestBtn = UIButton()
        let testLongPress = UILongPressGestureRecognizer(target: self, action: #selector(deleteBtnLongPress))
        testLongPress.minimumPressDuration = 3
        testLongPress.allowableMovement = 30
        longPressTestBtn.addGestureRecognizer(testLongPress)
        addSubview(longPressTestBtn)
        longPressTestBtn.snp.makeConstraints { make in
            make.right.equalTo(addBtn.snp.left).offset(SCRXFrom(-20))
            make.centerY.equalTo(addBtn)
        }
        
        editBtn = UIButton(normalImageName: "share_delete", target: self, action: #selector(editBtnClick))
        let editLongPress = UILongPressGestureRecognizer(target: self, action: #selector(deleteBtnLongPress))
        editLongPress.minimumPressDuration = 3
        editLongPress.allowableMovement = 30
        editBtn.addGestureRecognizer(editLongPress)
        addSubview(editBtn)
        editBtn.snp.makeConstraints { make in
            make.right.equalTo(addBtn.snp.left).offset(SCRXFrom(-20))
            make.centerY.equalTo(addBtn)
        }
        
        sortBtn = UIButton(normalImageName: "space_sort", target: self, action: #selector(sortBtnClick))
        addSubview(sortBtn)
        sortBtn.snp.makeConstraints { make in
            make.right.equalTo(editBtn.snp.left).offset(SCRXFrom(-20))
            make.centerY.equalTo(editBtn)
        }
        
        syncBtn = UIButton(normalImageName: "sync_failed", target: self, action: #selector(syncBtnClick))
        syncBtn.isHidden = true
        addSubview(syncBtn)
        syncBtn.snp.makeConstraints { make in
            make.right.equalTo(sortBtn.snp.left).offset(SCRXFrom(-20))
            make.centerY.equalTo(sortBtn)
        }
        
    }

}
