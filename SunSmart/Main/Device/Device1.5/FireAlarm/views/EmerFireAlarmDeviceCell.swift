//
//  EmerFireAlarmDeviceCell.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/22.
//
// 设备页的列表的cell
import UIKit

class EmerFireAlarmDeviceCell: UICollectionViewCell {
    
    /// 图标
    var iconImageView: UIImageView!
    /// 名称
    var nameLabel: UILabel!
    var deleteBtn: UIButton!
    var failedImageView: UIImageView!
    var warningIcon : UIImageView!
    private var status: EmerFireStatus = .unboundDevice
    
    var deleteActionCallback: ((DeviceEmerFireData)->Void)?
    private var device: DeviceEmerFireData?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        layer.shadowColor = RGB(0, 0, 0, 0.07).cgColor
        layer.shadowOffset = CGSizeMake(0,2)
        layer.shadowOpacity = 1
        layer.shadowRadius = 4
        
        iconImageView = UIImageView(image: UIImage(named: "group_00"))
        contentView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview().offset(SCRYFrom(-10))
        }
        
        warningIcon = UIImageView(image: UIImage(named: "Frame15"))
        contentView.addSubview(warningIcon)
        warningIcon.snp.makeConstraints { make in
            make.right.equalTo(iconImageView.snp.left).offset(SCRYFrom(-5))
            make.top.equalToSuperview().offset(SCRYFrom(10))
        }
        
        nameLabel = UILabel(text: nil, textColor: RGB(64, 79, 102), fontSize: 14, fontWeight: .light)
        nameLabel.textAlignment = .center
        nameLabel.lineBreakMode = .byTruncatingHead
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(18))
            make.right.equalTo(SCRXFrom(-18))
            make.bottom.equalTo(SCRYFrom(-17))
        }
        
        deleteBtn = UIButton(normalImageName: "scene_delete", target: self, action: #selector(deleteBtnClick))
        deleteBtn.isHidden = true
        contentView.addSubview(deleteBtn)
        deleteBtn.snp.makeConstraints { make in
            make.right.top.equalToSuperview()
        }
        
        failedImageView = UIImageView(image: UIImage(named: "schedule_sync_failed"))
        failedImageView.isHidden = true
        contentView.addSubview(failedImageView)
        failedImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(18))
            make.top.equalTo(SCRYFrom(18))
        }
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = frame.height * 0.5
        
        updateUI()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        device = nil
        status = .unboundDevice
        warningIcon.isHidden = true
        deleteBtn.isHidden = true
        deleteActionCallback = nil
        deleteDashedBorder()
    }
    
    private func updateUI() {
        switch status {
        case .unboundDevice:
            addDashedBorder()
        default:
            deleteDashedBorder()
        }
    }
    
    func configCell(name: String, status: EmerFireStatus){
        nameLabel.text = name
        self.status = status
        configCellSatus(status: status)
    }

    func configCell(device: DeviceEmerFireData, editing: Bool) {
        self.device = device
        deleteBtn.isHidden = !editing
        configCell(name: device.name, status: device.displayStatus)
    }
    
    func configCellSatus(status: EmerFireStatus){
        switch status {
        case .onlineBoundDevice:
            iconImageView.image = UIImage(named: "group_00")
            warningIcon.isHidden = true
            self.deleteDashedBorder()
        case .offlineBoundDevice:
            warningIcon.isHidden = true
            iconImageView.image = UIImage(named: "device_offline_Emergency")
            self.deleteDashedBorder()
        case .unboundDevice:
            warningIcon.isHidden = true
            iconImageView.image = UIImage(named: "group_00")
            self.addDashedBorder()
        case .syncIssueDevice:
            warningIcon.isHidden = true
            iconImageView.image = UIImage(named: "group_11")
            self.deleteDashedBorder()
        case .repairRequiredDevice:
            warningIcon.isHidden = true
            iconImageView.image = UIImage(named: "group_13")
            self.deleteDashedBorder()
        case .gatewayUnassignedWarning:
            warningIcon.isHidden = false
            iconImageView.image = UIImage(named: "group_00")
            self.deleteDashedBorder()
        }
    }
    
    @objc private func deleteBtnClick() {
        guard let device else { return }
        deleteActionCallback?(device)
    }
    
}
