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
        let details: [EmerFireAlarmStatusSetView.DetailViewModel]
        let statusImageName: String?

        init(
            title: String,
            details: [EmerFireAlarmStatusSetView.DetailViewModel],
            statusImageName: String? = nil
        ) {
            self.title = title
            self.details = details
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

    private lazy var detailStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .leading
        stackView.spacing = SCRYFrom(4)
        return stackView
    }()

    private lazy var rightValueStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .trailing
        stackView.spacing = SCRYFrom(4)
        return stackView
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
        resetStackView(detailStackView)
        resetStackView(rightValueStackView)

        viewModel.details.forEach { detail in
            detailStackView.addArrangedSubview(makeSubtitleLabel(text: detail.subtitle))
            rightValueStackView.addArrangedSubview(makeValueLabel(text: detail.value))
        }

        statusImageView.image = viewModel.statusImageName.flatMap { UIImage(named: $0) }
        statusImageView.isHidden = viewModel.statusImageName == nil
    }

    private func setupUI() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        contentView.addSubview(rightValueStackView)
        rightValueStackView.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(-Layout.horizontalInset)
            make.bottom.equalToSuperview().offset(-Layout.bottomInset)
        }

        contentView.addSubview(statusImageView)
        statusImageView.snp.makeConstraints { make in
            make.right.equalTo(rightValueStackView.snp.left).offset(-SCRXFrom(10))
            make.centerY.equalTo(rightValueStackView)
            make.width.height.equalTo(SCRXFrom(14))
        }

        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(Layout.horizontalInset)
            make.top.equalToSuperview().offset(Layout.topInset)
            make.right.lessThanOrEqualTo(statusImageView.snp.left).offset(-SCRXFrom(12))
        }

        contentView.addSubview(detailStackView)
        detailStackView.snp.makeConstraints { make in
            make.left.equalTo(titleLabel)
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(6))
            make.right.lessThanOrEqualTo(statusImageView.snp.left).offset(-SCRXFrom(12))
            make.bottom.equalToSuperview().offset(-Layout.bottomInset)
        }
    }

    private func makeSubtitleLabel(text: String) -> UILabel {
        let label = UILabel(text: text, textColor: AssistText_Color, fontSize: 11, fontWeight: .light)
        label.numberOfLines = 1
        return label
    }

    private func makeValueLabel(text: String) -> UILabel {
        let label = UILabel(text: text, textColor: Bar_Color, fontSize: 13, fontWeight: .light)
        label.textAlignment = .right
        label.numberOfLines = 1
        return label
    }

    private func resetStackView(_ stackView: UIStackView) {
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }
}
