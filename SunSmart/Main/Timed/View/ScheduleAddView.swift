//
//  ScheduleAddView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/1/5.
//

import UIKit

class ScheduleAddView: UIView {
    
    var scrollView: UIScrollView!
    var contentView: UIView!
 
    /// name+enable
    private var infoView: UIView!
    private var nameField: UITextField!
    private var enabledSwitch: UISwitch!

    
    
//    private var enabledSwitch: UISwitch!
    
}

class ScheduleAddTargetView: UIView {
    
    private var targetLabel: UILabel!
    private var tableView: UITableView!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        targetLabel = UILabel(text: "target".localizedString, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        addSubview(targetLabel)
        targetLabel.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.left.equalTo(SCRXFrom(12))
        }
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.backgroundColor = .white
        tableView.layer.cornerRadius = SCRYFrom(10)
        
        addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(targetLabel.snp.bottom).offset(SCRYFrom(8))
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

class ScheduleAddTargetViewCell: UITableViewCell {
    var selectBtn: UIButton!
    var contentLabel: UILabel!
    var titleLabel: UILabel!
    var arrowImageView: UIImageView!
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func selectBtnAction() {
        
    }
    
    private func setupUI() {
        selectBtn = UIButton(normalImageName: "schedule_target_select_un", selectedImageName: "schedule_target_select", target: self, action: #selector(selectBtnAction))
        contentView.addSubview(selectBtn)
        selectBtn.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.left.equalTo(SCRXFrom(8))
        }
        
        titleLabel = UILabel(text: "Devices", textColor: RGB(39, 37, 54), fontSize: 15, fontWeight: .light)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(selectBtn.snp.right).offset(SCRXFrom(4))
            make.centerY.equalToSuperview()
        }
        
        arrowImageView = UIImageView(image: UIImage(named: "arrow_light_right"))
        contentView.addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-4))
            make.centerY.equalToSuperview()
        }
        
        contentLabel = UILabel(text: "Select devices", textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(contentLabel)
        contentLabel.snp.makeConstraints { make in
            make.right.equalTo(arrowImageView.snp.left)
            make.centerY.equalTo(arrowImageView)
        }
        
    }
}

