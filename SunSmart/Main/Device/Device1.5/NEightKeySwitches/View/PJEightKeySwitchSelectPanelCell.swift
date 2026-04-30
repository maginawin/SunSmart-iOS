//
//  PJEightKeySwitchSelectPanelCell.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

final class PJEightKeySwitchSelectPanelCell: UITableViewCell {

    private let panelView = PJEightKeySwitchPanelView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = Background_Color
        contentView.backgroundColor = .clear

        contentView.addSubview(panelView)
        panelView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFrom(8))
            make.bottom.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(definition: PJEightKeySwitchPanelDefinition, selected: Bool) {
        panelView.configure(definition: definition, mode: .preview)
        panelView.layer.cornerRadius = 12
        panelView.layer.masksToBounds = true
        panelView.layer.borderWidth = selected ? 1 : 0
        panelView.layer.borderColor = selected ? Bar_Color.cgColor : UIColor.clear.cgColor
    }

    func preferredHeight(for width: CGFloat) -> CGFloat {
        panelView.preferredHeight(for: width - SCRXFrom(32)) + SCRYFrom(8)
    }
}
