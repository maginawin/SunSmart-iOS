//
//  DeviceBottomBtnView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/23.
//

import UIKit

class DeviceBottomBtnView: UIView {

    var lineView: UIView!
    var btnLineView: UIView!
    var deleteBtn: UIButton!
    var saveBtn: UIButton!
    var createBtn: UIButton!

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .white

        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showCreateUI() {

        saveBtn.isHidden = true
        btnLineView.isHidden = true
        deleteBtn.isHidden = true
        createBtn.isHidden = false
    }

    func showEditUI() {

        saveBtn.isHidden = false
        btnLineView.isHidden = false
        deleteBtn.isHidden = false
        createBtn.isHidden = true

        saveBtn.snp.remakeConstraints { make in
            make.right.top.equalToSuperview()
            make.left.equalTo(self.snp.centerX)
            make.height.equalTo(deleteBtn)
        }
    }

    func showSaveOnlyUI() {

        saveBtn.isHidden = false
        btnLineView.isHidden = true
        deleteBtn.isHidden = true
        createBtn.isHidden = true

        saveBtn.snp.remakeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(56))
        }
    }

    private func setupUI() {

        lineView = UIView()
        lineView.backgroundColor = Line_Color
        addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(1)
        }

        deleteBtn = UIButton(title: "alert_item_delete".localizedString, titleSize: 16, titleWeight: .light, titleColor: Red_Color)
        deleteBtn.setTitleColor(Red_Color.withAlphaComponent(0.5), for: .disabled)
        addSubview(deleteBtn)
        deleteBtn.snp.makeConstraints { make in
            make.left.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(56))
            make.right.equalTo(self.snp.centerX)
        }

        btnLineView = UIView()
        btnLineView.backgroundColor = Line_Color1
        addSubview(btnLineView)
        btnLineView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalTo(deleteBtn)
            make.width.equalTo(1)
            make.height.equalTo(SCRYFrom(40))
        }

        saveBtn = UIButton(title: "save".localizedString, titleSize: 16, titleWeight: .light, titleColor: Bar_Color)
        saveBtn.setTitleColor(Bar_Color.withAlphaComponent(0.5), for: .disabled)
        addSubview(saveBtn)
        saveBtn.snp.makeConstraints { make in
            make.right.top.equalToSuperview()
            make.left.equalTo(self.snp.centerX)
            make.height.equalTo(deleteBtn)
        }

        createBtn = UIButton(title: "CREATE".localizedString, titleSize: 16, titleWeight: .light, titleColor: Bar_Color)
        createBtn.isHidden = true
        addSubview(createBtn)
        createBtn.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(deleteBtn)
        }

    }

}
