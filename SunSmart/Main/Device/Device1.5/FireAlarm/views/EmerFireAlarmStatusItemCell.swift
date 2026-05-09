//
//  EmerFireAlarmStatusItemCell.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/21.
//

import UIKit
import SnapKit

final class EmerFireAlarmStatusItemCell: UITableViewCell {

    struct ViewModel {
        let title: String
        let subtitle: String
        let value: String
        let statusImageName: String?

        init(title: String, subtitle: String, value: String, statusImageName: String? = nil) {
            self.title = title
            self.subtitle = subtitle
            self.value = value
            self.statusImageName = statusImageName
        }
    }

    private enum Layout {
        static let horizontalInset = SCRXFrom(20)
        static let topInset = SCRYFrom(14)
        static let bottomInset = SCRYFrom(12)
    }

    private lazy var titleLabel: UILabel = {
        let label = UILabel(text: nil, textColor: Title_Color, fontSize: 13, fontWeight: .regular)
        return label
    }()

    private lazy var subtitleLabel: UILabel = {
        let label = UILabel(text: nil, textColor: AssistText_Color, fontSize: 11, fontWeight: .light)
        return label
    }()

    private lazy var valueLabel: UILabel = {
        let label = UILabel(text: nil, textColor: Bar_Color, fontSize: 13, fontWeight: .light)
        label.textAlignment = .right
        return label
    }()

    private lazy var statusImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with viewModel: ViewModel) {
        titleLabel.text = viewModel.title
        subtitleLabel.text = viewModel.subtitle
        valueLabel.text = viewModel.value
        statusImageView.image = viewModel.statusImageName.flatMap { UIImage(named: $0) }
        statusImageView.isHidden = viewModel.statusImageName == nil
    }

    private func setupUI() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        contentView.addSubview(valueLabel)
        valueLabel.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(-Layout.horizontalInset)
            make.centerY.equalToSuperview()
        }

        contentView.addSubview(statusImageView)
        statusImageView.snp.makeConstraints { make in
            make.right.equalTo(valueLabel.snp.left).offset(-SCRXFrom(10))
            make.centerY.equalTo(valueLabel)
            make.width.height.equalTo(SCRXFrom(14))
        }

        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(Layout.horizontalInset)
            make.top.equalToSuperview().offset(Layout.topInset)
            make.right.lessThanOrEqualTo(statusImageView.snp.left).offset(-SCRXFrom(12))
        }

        contentView.addSubview(subtitleLabel)
        subtitleLabel.snp.makeConstraints { make in
            make.left.equalTo(titleLabel)
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(6))
            make.right.lessThanOrEqualTo(statusImageView.snp.left).offset(-SCRXFrom(12))
            make.bottom.equalToSuperview().offset(-Layout.bottomInset)
        }
    }
}
