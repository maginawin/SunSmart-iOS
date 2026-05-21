//
//  PJEightKeySwitchMonitorPanelView.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit
import SnapKit

final class PJEightKeySwitchMonitorPanelView: UIView {

    var keyTapAction: ((Int) -> Void)?
    var dimmingLongPressAction: ((PJEightKeySwitchMonitorViewModel.KeyItem.Direction) -> Void)?
    var autoLongPressAction: (() -> Void)?
    var disabledTapAction: (() -> Void)?

    static var preferredWidth: CGFloat {
        Layout.sideInset * 2 + Layout.cellWidth * 2 + Layout.columnSpacing * 2
    }

    private enum Layout {
        static let panelCornerRadius = SCRYFrom(18)
        static let topInset = SCRYFrom(14)
        static let sideInset = SCRXFrom(12)
        static let bottomInset = SCRYFrom(16)
        static let cellWidth = SCRXFrom(104)
        static let cellHeight = SCRYFrom(94)
        static let columnSpacing = SCRXFrom(12)
        static let rowSpacing = SCRYFrom(11)
        static let headerHeight = SCRYFrom(18)
    }

    private let contentView = UIView()
    private let headerView = UIView()
    private let indicatorView = UIView()
    private let headerDividerView = UIView()
    private let verticalDividerView = UIView()
    private let horizontalDividerViews = [UIView(), UIView(), UIView()]
    private let panelOverlayView = UIView()
    private var keyViews: [PJEightKeySwitchMonitorKeyView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(items: [PJEightKeySwitchMonitorViewModel.KeyItem], enabled: Bool) {
        guard items.count == keyViews.count else { return }
        zip(keyViews, items).enumerated().forEach { index, pair in
            let (keyView, item) = pair
            keyView.configure(item: item, enabled: enabled)
            keyView.tapAction = nil
            keyView.longPressAction = nil
            keyView.disabledTapAction = nil
            if enabled {
                keyView.tapAction = { [weak self] in
                    self?.keyTapAction?(index)
                }
            }
            if case let .dimming(direction) = item.style {
                keyView.longPressAction = { [weak self] in
                    self?.dimmingLongPressAction?(direction)
                }
            } else if case .toggle(let kind) = item.style, kind == .on {
                keyView.longPressAction = { [weak self] in
                    self?.autoLongPressAction?()
                }
            }
            if !enabled {
                keyView.disabledTapAction = { [weak self] in
                    self?.disabledTapAction?()
                }
            }
        }
        contentView.backgroundColor = enabled ? .white : RGB(241, 243, 248)
        indicatorView.backgroundColor = enabled ? RGB(43, 209, 104) : RGB(204, 208, 219)
        panelOverlayView.isHidden = true
        isUserInteractionEnabled = true
    }

    private func setupUI() {
        backgroundColor = .clear

        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = Layout.panelCornerRadius
        contentView.layer.shadowColor = RGB(43, 53, 92, 0.12).cgColor
        contentView.layer.shadowOpacity = 1
        contentView.layer.shadowRadius = 14
        contentView.layer.shadowOffset = CGSize(width: 0, height: 6)
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        headerView.backgroundColor = .clear
        contentView.addSubview(headerView)
        headerView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(Layout.topInset)
            make.left.equalToSuperview().offset(Layout.sideInset)
            make.right.equalToSuperview().offset(-Layout.sideInset)
            make.height.equalTo(Layout.headerHeight)
        }

        indicatorView.layer.cornerRadius = SCRXFrom(3)
        headerView.addSubview(indicatorView)
        indicatorView.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.right.equalToSuperview().offset(-SCRXFrom(2))
            make.width.height.equalTo(SCRXFrom(6))
        }

        headerDividerView.backgroundColor = RGB(239, 241, 247)
        contentView.addSubview(headerDividerView)
        headerDividerView.snp.makeConstraints { make in
            make.top.equalTo(headerView.snp.bottom).offset(SCRYFrom(6))
            make.left.equalToSuperview()
            make.right.equalToSuperview()
            make.height.equalTo(1)
        }

        for _ in 0..<8 {
            let keyView = PJEightKeySwitchMonitorKeyView()
            contentView.addSubview(keyView)
            keyViews.append(keyView)
        }

        let leftViews = [keyViews[0], keyViews[2], keyViews[4], keyViews[6]]
        let rightViews = [keyViews[1], keyViews[3], keyViews[5], keyViews[7]]

        leftViews.enumerated().forEach { index, itemView in
            itemView.snp.makeConstraints { make in
                make.left.equalToSuperview().offset(Layout.sideInset)
                make.width.equalTo(Layout.cellWidth)
                make.height.equalTo(Layout.cellHeight)
                make.top.equalTo(headerView.snp.bottom).offset(SCRYFrom(12) + CGFloat(index) * (Layout.cellHeight + Layout.rowSpacing*2))
            }
        }

        rightViews.enumerated().forEach { index, itemView in
            itemView.snp.makeConstraints { make in
                make.left.equalTo(leftViews[index].snp.right).offset(Layout.columnSpacing*2)
                make.width.equalTo(Layout.cellWidth)
                make.height.equalTo(Layout.cellHeight)
                make.top.equalTo(leftViews[index])
            }
        }

        verticalDividerView.backgroundColor = RGB(239, 241, 247)
        contentView.addSubview(verticalDividerView)
        verticalDividerView.snp.makeConstraints { make in
            make.top.equalTo(leftViews.first!.snp.top).offset(Layout.rowSpacing)
            make.bottom.equalTo(leftViews.last!.snp.bottom)
            make.centerX.equalToSuperview()
            make.width.equalTo(1)
        }

        horizontalDividerViews.enumerated().forEach { index, divider in
            divider.backgroundColor = RGB(239, 241, 247)
            contentView.addSubview(divider)
            divider.snp.makeConstraints { make in
                make.left.equalToSuperview()
                make.right.equalToSuperview()
                make.height.equalTo(1)
                make.top.equalTo(leftViews[index].snp.bottom).offset(Layout.rowSpacing)
            }
        }

        panelOverlayView.isHidden = true
    }
}
