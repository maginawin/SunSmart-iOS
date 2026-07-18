import UIKit
import SnapKit
import NordicSigMeshSDK

final class SimulateFaultViewController: UIViewController {
    private enum Layout {
        static let dimmingAlpha: CGFloat = 0.30
        static let contentCornerRadius: CGFloat = 20
    }

    private let space: SpaceData
    private let node: Node
    private let dimmingControl = UIControl()
    private let contentView = UIView()
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let headerView = UIView()
    private let headerIconContainerView = UIView()
    private let headerImageView = UIImageView(image: UIImage(named: "black_debug"))
    private let headerLabel = UILabel()
    private var contentHeightConstraint: Constraint?
    private var stackBottomConstraint: Constraint?
    private var lastPresentationWidth: CGFloat = 0
    private var lastPresentationHeight: CGFloat = 0
    private var lastSafeAreaBottom: CGFloat = -1
    private var isSending = false

    init(space: SpaceData, node: Node) {
        self.space = space
        self.node = node
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(spacePermissionDidChange),
            name: .init(spacePermissionChangedNotificaitonName),
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePresentationLayoutIfNeeded()
    }

    private func setupUI() {
        view.backgroundColor = .clear

        dimmingControl.backgroundColor = UIColor.black.withAlphaComponent(Layout.dimmingAlpha)
        dimmingControl.addTarget(self, action: #selector(dismissFromBackground), for: .touchUpInside)

        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = Layout.contentCornerRadius
        contentView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        contentView.clipsToBounds = true

        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never

        stackView.axis = .vertical
        stackView.spacing = SimulateFaultPresentationMetrics.sectionSpacing

        headerImageView.contentMode = .scaleAspectFit
        headerLabel.text = "simulate_fault".localizedString
        headerLabel.textColor = UIColor(
            red: 46 / 255,
            green: 49 / 255,
            blue: 93 / 255,
            alpha: 1
        )
        headerLabel.font = .systemFont(ofSize: 14, weight: .regular)

        view.addSubview(dimmingControl)
        view.addSubview(contentView)
        contentView.addSubview(scrollView)
        scrollView.addSubview(stackView)
        stackView.addArrangedSubview(headerView)
        stackView.setCustomSpacing(
            SimulateFaultPresentationMetrics.headerToSectionSpacing,
            after: headerView
        )
        headerView.addSubview(headerIconContainerView)
        headerIconContainerView.addSubview(headerImageView)
        headerView.addSubview(headerLabel)

        makeSections().forEach { section in
            section.onAction = { [weak self] action in
                self?.handleAction(action)
            }
            stackView.addArrangedSubview(section)
        }

        dimmingControl.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        contentView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            contentHeightConstraint = make.height.equalTo(0).constraint
        }
        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        stackView.snp.makeConstraints { make in
            make.top.equalTo(scrollView.contentLayoutGuide)
                .offset(SimulateFaultPresentationMetrics.contentTopInset)
            make.left.equalTo(scrollView.contentLayoutGuide)
                .offset(SimulateFaultPresentationMetrics.contentHorizontalInset)
            make.right.equalTo(scrollView.contentLayoutGuide)
                .offset(-SimulateFaultPresentationMetrics.contentHorizontalInset)
            stackBottomConstraint = make.bottom.equalTo(scrollView.contentLayoutGuide).constraint
            make.width.equalTo(scrollView.frameLayoutGuide)
                .offset(-SimulateFaultPresentationMetrics.contentHorizontalInset * 2)
        }
        headerView.snp.makeConstraints { make in
            make.height.equalTo(SimulateFaultPresentationMetrics.headerHeight)
        }
        headerIconContainerView.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(4)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(30)
        }
        headerImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(30)
        }
        headerLabel.snp.makeConstraints { make in
            make.left.equalTo(headerIconContainerView.snp.right).offset(2)
            make.right.equalToSuperview().offset(-4)
            make.centerY.equalToSuperview()
        }
    }

    private func updatePresentationLayoutIfNeeded() {
        let width = view.bounds.width
        let height = view.bounds.height
        let safeAreaBottom = view.safeAreaInsets.bottom
        guard
            width > 0,
            width != lastPresentationWidth
                || height != lastPresentationHeight
                || safeAreaBottom != lastSafeAreaBottom
        else {
            return
        }

        lastPresentationWidth = width
        lastPresentationHeight = height
        lastSafeAreaBottom = safeAreaBottom

        let bottomInset = SimulateFaultPresentationMetrics.bottomInset(
            safeAreaBottom: safeAreaBottom
        )
        let desiredHeight = SimulateFaultPresentationMetrics.contentHeight(
            availableWidth: width,
            safeAreaBottom: safeAreaBottom
        )
        let availableHeight = height

        stackBottomConstraint?.update(offset: -bottomInset)
        contentHeightConstraint?.update(offset: min(desiredHeight, availableHeight))
        scrollView.isScrollEnabled = desiredHeight > availableHeight
    }

    private func makeSections() -> [SimulateFaultSectionView] {
        let motion = SimulateFaultSectionView(configuration: .init(
            titleKey: "simulate_fault_motion_sensor",
            tagKey: "simulate_fault_minor_3",
            tagStyle: .init(
                textColor: UIColor(red: 212 / 255, green: 138 / 255, blue: 0, alpha: 1),
                backgroundColor: UIColor(red: 255 / 255, green: 247 / 255, blue: 226 / 255, alpha: 1)
            ),
            items: [
                .init(titleKey: "simulate_fault_normal", action: .motionSensor(.normal)),
                .init(titleKey: "simulate_fault_fault", action: .motionSensor(.fault))
            ]
        ))
        let photocell = SimulateFaultSectionView(configuration: .init(
            titleKey: "simulate_fault_photocell_sensor",
            tagKey: "simulate_fault_major_2",
            tagStyle: .init(
                textColor: UIColor(red: 224 / 255, green: 85 / 255, blue: 66 / 255, alpha: 1),
                backgroundColor: UIColor(red: 255 / 255, green: 237 / 255, blue: 234 / 255, alpha: 1)
            ),
            items: [
                .init(titleKey: "simulate_fault_normal", action: .photocellSensor(.normal)),
                .init(titleKey: "simulate_fault_fault", action: .photocellSensor(.fault))
            ]
        ))
        let light = SimulateFaultSectionView(configuration: .init(
            titleKey: "simulate_fault_light_status",
            tagKey: "simulate_fault_critical_1",
            tagStyle: .init(
                textColor: UIColor(red: 189 / 255, green: 53 / 255, blue: 47 / 255, alpha: 1),
                backgroundColor: UIColor(red: 255 / 255, green: 228 / 255, blue: 226 / 255, alpha: 1)
            ),
            items: [
                .init(titleKey: "simulate_fault_normal", action: .lightStatus(.normal)),
                .init(titleKey: "simulate_fault_dim", action: .lightStatus(.dim)),
                .init(titleKey: "simulate_fault_flicker", action: .lightStatus(.flicker)),
                .init(titleKey: "simulate_fault_dim_flicker", action: .lightStatus(.dimFlicker)),
                .init(titleKey: "simulate_fault_off", action: .lightStatus(.off))
            ]
        ))
        return [motion, photocell, light]
    }

    private func handleAction(_ action: SimulateFaultAction) {
        guard space.deviceOperates.contains(.edit) else {
            dismiss(animated: true)
            return
        }
        guard !isSending else { return }

        isSending = true
        let payload = SimulateFaultRequestPayload(
            siteId: space.siteId,
            spaceId: space.id,
            nodeId: node.uuid.uuidString,
            alert: action.alertPayload,
            nodeAddress: node.primaryUnicastAddress.hex,
            date: Date()
        )
        XWHUDManager.showCustomHUD(withMessage: "simulate_fault_sending".localizedString, isWindow: true)
        NetworkRequest.shared.request(.simulateFault(payload: payload)) { [weak self] result in
            XWHUDManager.hide()
            self?.isSending = false
            switch result {
            case .success:
                XWHUDManager.showSuccessTipHUD("successful".localizedString)
            case .failure:
                XWHUDManager.showErrorTipHUD("failed".localizedString)
            }
        }
    }

    @objc private func dismissFromBackground() {
        dismiss(animated: true)
    }

    @objc private func spacePermissionDidChange() {
        guard !space.deviceOperates.contains(.edit) else { return }
        dismiss(animated: true)
    }
}
