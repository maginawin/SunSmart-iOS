//
//  EmerFireAlarmStatusLegendHeaderView.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/21.
//

//状态设置列表顶部四个按钮
import UIKit
import SnapKit

final class EmerFireAlarmStatusLegendHeaderView: UIView {

    private enum Layout {
        static let height = SCRYFrom(32)
        static let horizontalInset = SCRXFrom(24)
        static let itemSpacing = SCRXFrom(16)
        static let indicatorSize = SCRXFrom(20)
        static let cornerRadius = SCRYFrom(2)
        static let containerCornerRadius = SCRYFrom(10)
    }

    private final class LegendItemView: UIView {
        private lazy var indicatorView: UIView = {
            let view = UIView()
            view.layer.cornerRadius = Layout.cornerRadius
            view.layer.masksToBounds = true
            return view
        }()

        private lazy var indicatorImageView: UIImageView = {
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFit
            imageView.isHidden = true
            return imageView
        }()

        private lazy var titleLabel: UILabel = {
            let label = UILabel(text: nil, textColor: RGB(64, 79, 102), fontSize: 12, fontWeight: .light)
            return label
        }()

        init(title: String, color: UIColor? = nil, image: UIImage? = nil) {
            super.init(frame: .zero)
            titleLabel.text = title
            setupUI()
            if let image {
                indicatorImageView.image = image.withRenderingMode(.alwaysOriginal)
                indicatorImageView.isHidden = false
                indicatorView.isHidden = true
            } else {
                indicatorView.backgroundColor = color
            }
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func setupUI() {
            addSubview(indicatorView)
            indicatorView.snp.makeConstraints { make in
                make.left.centerY.equalToSuperview()
                make.width.height.equalTo(Layout.indicatorSize)
            }

            addSubview(indicatorImageView)
            indicatorImageView.snp.makeConstraints { make in
                make.edges.equalTo(indicatorView)
            }

            addSubview(titleLabel)
            titleLabel.snp.makeConstraints { make in
                make.left.equalTo(indicatorView.snp.right).offset(SCRXFrom(4))
                make.centerY.equalToSuperview()
                make.right.equalToSuperview()
            }
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Layout.height)
    }

    private lazy var triggeredItem = LegendItemView(title: "efc_status_triggered".localizedString, image: UIImage(named: EmergencyFireControllerIconName.Monitor.StatusSet.powerLossActive))
    private lazy var resumeItem = LegendItemView(title: "efc_status_resume".localizedString, image: UIImage(named: EmergencyFireControllerIconName.Monitor.StatusSet.fireActive))
    private lazy var inactiveItem = LegendItemView(title: "efc_status_inactive".localizedString, image: UIImage(named: EmergencyFireControllerIconName.Monitor.StatusSet.inactive))

    private lazy var stackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [triggeredItem, resumeItem, inactiveItem])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .equalSpacing
        stackView.spacing = Layout.itemSpacing
        return stackView
    }()

    private lazy var containerView: UIView = {
        let view = UIView()
        view.backgroundColor = RGB(250, 250, 250)
        view.layer.cornerRadius = Layout.containerCornerRadius
        view.layer.masksToBounds = true
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = .clear

        addSubview(containerView)
        containerView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        containerView.addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(Layout.horizontalInset)
            make.top.bottom.equalToSuperview()
        }
    }
}
