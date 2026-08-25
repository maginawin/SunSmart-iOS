//
//  DeviceNameFilterMenuView.swift
//  SunSmart
//
//  Created by One on 2026/7/22.
//

import UIKit

final class DeviceNameFilterMenuView: UIControl {
    private static let menuWidth = SCRXFrom(200)
    private static let rowHeight = SCRYFrom(44)
    private static let dividerHeight = 1.0

    private let contentView = UIView()
    private var onSearch: (() -> Void)?
    private var onReset: (() -> Void)?

    static func show(
        from sourceView: UIView,
        onSearch: @escaping () -> Void,
        onReset: @escaping () -> Void
    ) {
        let window = UIApplication.shared.keyWindow()
        window.subviews.compactMap { $0 as? DeviceNameFilterMenuView }
            .forEach { $0.removeFromSuperview() }

        let menu = DeviceNameFilterMenuView(frame: window.bounds)
        menu.onSearch = onSearch
        menu.onReset = onReset
        menu.setupUI(from: sourceView, in: window)
        window.addSubview(menu)
    }

    private func setupUI(from sourceView: UIView, in window: UIWindow) {
        backgroundColor = .clear
        accessibilityViewIsModal = true
        addTarget(self, action: #selector(dismiss), for: .touchUpInside)

        let menuHeight = Self.rowHeight * 2 + Self.dividerHeight
        let safeInsets = window.safeAreaInsets
        let sourceRect = sourceView.convert(sourceView.bounds, to: window)
        let minimumX = safeInsets.left + SCRXFrom(16)
        let maximumX = window.bounds.width - safeInsets.right - SCRXFrom(16) - Self.menuWidth
        let menuX = min(max(sourceRect.minX, minimumX), max(minimumX, maximumX))
        let minimumY = safeInsets.top + SCRYFrom(16)
        let maximumY = window.bounds.height - safeInsets.bottom - SCRYFrom(16) - menuHeight
        let preferredMenuY = sourceRect.minY - SCRYFrom(8) - menuHeight
        let fallbackMenuY = sourceRect.maxY + SCRYFrom(8)
        let menuY = preferredMenuY >= minimumY
            ? min(preferredMenuY, max(minimumY, maximumY))
            : min(max(fallbackMenuY, minimumY), max(minimumY, maximumY))

        contentView.frame = CGRect(x: menuX, y: menuY, width: Self.menuWidth, height: menuHeight)
        contentView.backgroundColor = RGB(74, 74, 74, 0.95)
        contentView.layer.cornerRadius = SCRYFrom(10)
        contentView.layer.shadowColor = UIColor.black.cgColor
        contentView.layer.shadowOpacity = 0.15
        contentView.layer.shadowRadius = 20
        contentView.layer.shadowOffset = CGSize(width: 0, height: -4)
        addSubview(contentView)

        let searchButton = makeButton(
            title: "device_filter_search_by_name".localizedString,
            action: #selector(searchButtonTapped)
        )
        searchButton.frame = CGRect(x: 0, y: 0, width: Self.menuWidth, height: Self.rowHeight)
        contentView.addSubview(searchButton)

        let dividerArea = UIView(frame: CGRect(
            x: 0,
            y: Self.rowHeight,
            width: Self.menuWidth,
            height: Self.dividerHeight
        ))
        contentView.addSubview(dividerArea)

        let divider = UIView(frame: CGRect(
            x: SCRXFrom(16),
            y: 0,
            width: Self.menuWidth - SCRXFrom(32),
            height: Self.dividerHeight
        ))
        divider.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        dividerArea.addSubview(divider)

        let resetButton = makeButton(title: "reset".localizedString, action: #selector(resetButtonTapped))
        resetButton.frame = CGRect(
            x: 0,
            y: Self.rowHeight + Self.dividerHeight,
            width: Self.menuWidth,
            height: Self.rowHeight
        )
        contentView.addSubview(resetButton)
    }

    private func makeButton(title: String, action: Selector) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.baseForegroundColor = .white
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 0,
            leading: SCRXFrom(16),
            bottom: 0,
            trailing: SCRXFrom(16)
        )

        let button = UIButton(configuration: configuration, primaryAction: nil)
        button.titleLabel?.font = FONTS(14)
        button.contentHorizontalAlignment = .left
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func searchButtonTapped() {
        let completion = onSearch
        removeFromSuperview()
        completion?()
    }

    @objc private func resetButtonTapped() {
        let completion = onReset
        removeFromSuperview()
        completion?()
    }

    @objc private func dismiss() {
        removeFromSuperview()
    }
}
