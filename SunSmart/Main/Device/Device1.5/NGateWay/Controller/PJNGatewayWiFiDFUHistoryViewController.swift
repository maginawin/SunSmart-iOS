//
//  PJNGatewayWiFiDFUHistoryViewController.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

final class PJNGatewayWiFiDFUHistoryViewController: UIViewController {

    private let viewModel = PJNGatewayWiFiDFUHistoryViewModel()
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stackView = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = viewModel.title
        view.backgroundColor = UIColor(hex: 0xF5F7FB)
        setupUI()
        render()
    }

    private func setupUI() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(stackView)

        scrollView.showsVerticalScrollIndicator = false
        stackView.axis = .vertical
        stackView.spacing = SCRYFrom(16)

        scrollView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }

        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalToSuperview()
        }

        stackView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(SCRYFrom(12))
            make.left.equalToSuperview().offset(SCRXFrom(16))
            make.right.equalToSuperview().offset(SCRXFrom(-16))
            make.bottom.equalToSuperview().offset(SCRYFrom(-20))
        }
    }

    private func render() {
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for (index, item) in viewModel.items.enumerated() {
            let cardView = PJNGatewayWiFiDFUHistoryCardView()
            cardView.configure(item: item)
            cardView.moreAction = { [weak self] in
                self?.viewModel.toggleExpand(at: index)
                self?.render()
            }
            stackView.addArrangedSubview(cardView)
        }
    }
}
