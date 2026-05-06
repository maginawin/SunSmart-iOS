//
//  PJEightKeySwitchesViewCell.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

final class PJEightKeySwitchesViewCell: UICollectionViewCell {

    var deleteActionCallback: ((DeviceSwitchData) -> Void)?

    private(set) var switchData: DeviceSwitchData?
    private var currentStatus: PJEightKeySwitchStatus?

    private lazy var iconImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "eight_key_switch_bound_enabled"))
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var nameLabel: UILabel = {
        let label = UILabel(text: nil, textColor: RGB(64, 79, 102), fontSize: 14, fontWeight: .light)
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingHead
        return label
    }()

    let deleteBtn: UIButton = {
        let button = UIButton(normalImageName: "scene_delete", target: nil, action: nil)
        button.isHidden = true
        return button
    }()

    func configure(with switchData: DeviceSwitchData, eightKeySwitch: PJEightKeySwitchData, editing: Bool) {
        self.switchData = switchData
        nameLabel.text = switchData.name
        iconImageView.image = UIImage(named: eightKeySwitch.displayIconAssetName) ?? UIImage(named: "eight_key_switch_bound_enabled")
        deleteBtn.isHidden = !editing
        applyStatus(eightKeySwitch.displayStatus)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .white
        layer.shadowColor = RGB(0, 0, 0, 0.07).cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowOpacity = 1
        layer.shadowRadius = 4

        contentView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview().offset(SCRYFrom(-10))
        }

        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(18))
            make.right.equalTo(SCRXFrom(-18))
            make.bottom.equalTo(SCRYFrom(-17))
        }

        contentView.addSubview(deleteBtn)
        deleteBtn.snp.makeConstraints { make in
            make.right.top.equalToSuperview()
        }
        deleteBtn.addTarget(self, action: #selector(deleteBtnClick), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height * 0.5
        updateStatusAppearance()
    }

    private func applyStatus(_ status: PJEightKeySwitchStatus) {
        currentStatus = status
        updateStatusAppearance()
    }

    private func updateStatusAppearance() {
        guard let currentStatus else { return }

        if bounds.height > 0 {
            layer.cornerRadius = bounds.height * 0.5
        }

        if currentStatus.needsDashedBorder {
            addDashedBorder()
        } else {
            deleteDashedBorder()
        }

        if currentStatus.needsDimmedBackground {
            backgroundColor = RGB(226, 226, 226)
        } else {
            backgroundColor = .white
        }
    }

    @objc private func deleteBtnClick() {
        guard let switchData else { return }
        deleteActionCallback?(switchData)
    }
}
