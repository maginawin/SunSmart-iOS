//
//  SiteEditViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/25.
//

import UIKit

final class SiteEditViewController: UIViewController {

    typealias SiteResultHostCompletion = (UIView) -> Void
    typealias FinishEditingHandler = (@escaping SiteResultHostCompletion) -> Void

    private let site: SiteData
    private var draft: SitePropsEditDraft
    private let coordinator: SitePropsEditCoordinator
    private let finishEditingHandler: FinishEditingHandler

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let nameLabel = UILabel()
    private let nameField = UITextField()
    private let nameTipLabel = UILabel()
    private let timeZoneTitleLabel = UILabel()
    private let notSyncedButton = UIButton()
    private let timeZoneContainer = UIView()
    private let timeZoneNameLabel = UILabel()
    private let timeZoneOffsetLabel = UILabel()
    private let localTimeLabel = UILabel()
    private let timeZoneButton = UIButton(type: .custom)
    private let siteIconTitleLabel = UILabel()
    private let collectionView: UICollectionView
    private let flowLayout = UICollectionViewFlowLayout()
    private let footerView = UIView()
    private let doneButton = UIButton()

    private let imageNames = (1...28).map { "site_\($0)" }
    private var selectedImageIndex: Int
    private var localTimeTimer: Timer?
    private var modalDismissalStateBeforeTimeZone: Bool?
    private var isCommitting = false

    var siteDidChange: (() -> Void)?

    init(
        site: SiteData,
        draft: SitePropsEditDraft,
        coordinator: SitePropsEditCoordinator,
        finishEditingHandler: @escaping FinishEditingHandler
    ) {
        self.site = site
        self.draft = draft
        self.coordinator = coordinator
        self.finishEditingHandler = finishEditingHandler
        self.selectedImageIndex = min(max(draft.values.imageId - 1, 0), 27)
        self.collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: flowLayout
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopLocalTimeUpdates()
        NotificationCenter.default.removeObserver(self)
        NSObject.cancelPreviousPerformRequests(withTarget: self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = site.name
        view.backgroundColor = Background_Color
        navigationController?.setNavigationBarBackgroundColor(color: .clear)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal),
            style: .done,
            target: self,
            action: #selector(close)
        )
        setupUI()
        registerLifecycleNotifications()
        updateTimeZoneDisplay()
        updatePendingDisplay()
        validateName(showLengthTip: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        restoreModalStackDismissalAfterTimeZoneIfNeeded()
        refreshLocalTime()
        startLocalTimeUpdates()
        if collectionView.firstShowFlashScrollIndicators {
            collectionView.flashScrollIndicatorsIfNeeded()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopLocalTimeUpdates()
    }

    private func setupUI() {
        setupFooter()
        setupScrollContent()
        setupNameSection()
        setupTimeZoneSection()
        setupSiteIconSection()
    }

    private func setupFooter() {
        footerView.backgroundColor = .white
        view.addSubview(footerView)
        footerView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(56) + (isIPad ? 0 : kSafeAreaBottomHeight))
        }

        let line = UIView()
        line.backgroundColor = Line_Color
        footerView.addSubview(line)
        line.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(0.5)
        }

        doneButton.setTitle("done".localizedString, for: .normal)
        doneButton.setTitleColor(Title_Color, for: .normal)
        doneButton.setTitleColor(RGB(139, 139, 139), for: .disabled)
        doneButton.titleLabel?.font = UIFont.systemFont(ofSize: SCRYFrom(16), weight: .light)
        doneButton.addTarget(self, action: #selector(doneBtnClick), for: .touchUpInside)
        footerView.addSubview(doneButton)
        doneButton.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(56))
        }
    }

    private func setupScrollContent() {
        scrollView.keyboardDismissMode = .onDrag
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.left.right.equalToSuperview()
            make.bottom.equalTo(footerView.snp.top)
        }

        scrollView.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.equalTo(scrollView.contentLayoutGuide)
            make.width.equalTo(scrollView.frameLayoutGuide)
        }
    }

    private func setupNameSection() {
        nameLabel.text = "name".localizedString
        nameLabel.textColor = RGB(39, 37, 54)
        nameLabel.font = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .light)
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalTo(SCRYFrom(16))
        }

        nameField.text = draft.values.siteName
        nameField.textColor = RGB(39, 37, 54)
        nameField.font = UIFont.systemFont(ofSize: SCRYFrom(14))
        nameField.layer.cornerRadius = SCRYFrom(10)
        nameField.layer.borderColor = RGB(220, 220, 220).cgColor
        nameField.layer.borderWidth = 0.5
        nameField.clearButtonMode = .whileEditing
        nameField.leftView = UIView(
            frame: CGRect(x: 0, y: 0, width: SCRXFrom(16), height: 1)
        )
        nameField.leftViewMode = .always
        nameField.returnKeyType = .done
        nameField.backgroundColor = .white
        nameField.delegate = self
        nameField.addTarget(self, action: #selector(nameFieldDidChange), for: .editingChanged)
        contentView.addSubview(nameField)
        nameField.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(nameLabel.snp.bottom).offset(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(40))
        }

        nameTipLabel.textColor = Red_Color
        nameTipLabel.font = UIFont.systemFont(ofSize: SCRYFrom(12), weight: .light)
        contentView.addSubview(nameTipLabel)
        nameTipLabel.snp.makeConstraints { make in
            make.left.equalTo(nameField).offset(SCRXFrom(4))
            make.right.equalTo(nameField).offset(SCRXFrom(-4))
            make.top.equalTo(nameField.snp.bottom).offset(SCRYFrom(2))
            make.height.equalTo(SCRYFrom(16))
        }
    }

    private func setupTimeZoneSection() {
        timeZoneTitleLabel.text = "site_time_zone_title".localizedString
        timeZoneTitleLabel.textColor = RGB(39, 37, 54)
        timeZoneTitleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .light)
        contentView.addSubview(timeZoneTitleLabel)
        timeZoneTitleLabel.snp.makeConstraints { make in
            make.left.equalTo(nameField)
            make.top.equalTo(nameTipLabel.snp.bottom).offset(SCRYFrom(12))
        }

        notSyncedButton.setTitle("site_not_synced_to_server".localizedString, for: .normal)
        notSyncedButton.setTitleColor(RGB(255, 72, 49), for: .normal)
        notSyncedButton.titleLabel?.font = UIFont.systemFont(ofSize: SCRYFrom(12), weight: .light)
        notSyncedButton.contentHorizontalAlignment = .right
        notSyncedButton.addTarget(self, action: #selector(doneBtnClick), for: .touchUpInside)
        contentView.addSubview(notSyncedButton)
        notSyncedButton.snp.makeConstraints { make in
            make.centerY.equalTo(timeZoneTitleLabel)
            make.right.equalTo(nameField)
            make.height.greaterThanOrEqualTo(SCRYFrom(44))
            make.width.greaterThanOrEqualTo(SCRXFrom(138))
        }

        timeZoneContainer.backgroundColor = .white
        timeZoneContainer.layer.cornerRadius = SCRYFrom(10)
        timeZoneContainer.layer.masksToBounds = true
        contentView.addSubview(timeZoneContainer)
        timeZoneContainer.snp.makeConstraints { make in
            make.left.right.equalTo(nameField)
            make.top.equalTo(timeZoneTitleLabel.snp.bottom).offset(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(44))
        }

        timeZoneNameLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14))
        timeZoneNameLabel.textColor = RGB(30, 35, 41)
        timeZoneContainer.addSubview(timeZoneNameLabel)
        timeZoneContainer.addSubview(timeZoneOffsetLabel)
        timeZoneNameLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(44))
            make.right.lessThanOrEqualTo(timeZoneOffsetLabel.snp.left).offset(SCRXFrom(-8))
        }

        let arrowImageView = UIImageView(image: UIImage(named: "arrow_light_right"))
        arrowImageView.contentMode = .center
        timeZoneContainer.addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.top.right.equalToSuperview()
            make.width.equalTo(SCRXFrom(30))
            make.height.equalTo(SCRYFrom(44))
        }

        timeZoneOffsetLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14))
        timeZoneOffsetLabel.textColor = RGB(100, 116, 139)
        timeZoneOffsetLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        timeZoneOffsetLabel.snp.makeConstraints { make in
            make.right.equalTo(arrowImageView.snp.left).offset(SCRXFrom(-8))
            make.centerY.equalTo(arrowImageView)
        }

        timeZoneButton.accessibilityLabel = "site_time_zone_title".localizedString
        timeZoneButton.addTarget(self, action: #selector(selectTimeZone), for: .touchUpInside)
        timeZoneContainer.addSubview(timeZoneButton)
        timeZoneButton.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        localTimeLabel.font = UIFont.systemFont(ofSize: SCRYFrom(12))
        localTimeLabel.textColor = RGB(154, 164, 183)
        contentView.addSubview(localTimeLabel)
        localTimeLabel.snp.makeConstraints { make in
            make.left.right.equalTo(timeZoneContainer)
            make.top.equalTo(timeZoneContainer.snp.bottom).offset(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(20))
        }
    }

    private func setupSiteIconSection() {
        siteIconTitleLabel.text = "site_icon".localizedString
        siteIconTitleLabel.textColor = RGB(39, 37, 54)
        siteIconTitleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .light)
        contentView.addSubview(siteIconTitleLabel)
        siteIconTitleLabel.snp.makeConstraints { make in
            make.left.equalTo(nameField)
            make.top.equalTo(localTimeLabel.snp.bottom).offset(SCRYFrom(16))
        }

        flowLayout.minimumLineSpacing = SCRXFrom(16)
        flowLayout.minimumInteritemSpacing = SCRXFrom(16)
        collectionView.backgroundColor = .clear
        collectionView.isScrollEnabled = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(ImageCollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        contentView.addSubview(collectionView)
        let columnCount: CGFloat = 4
        let rowCount = ceil(CGFloat(imageNames.count) / columnCount)
        let heightMultiplier = rowCount / columnCount
        let heightOffset = (rowCount - 1) * flowLayout.minimumLineSpacing
            - heightMultiplier * (columnCount - 1) * flowLayout.minimumInteritemSpacing
        collectionView.snp.makeConstraints { make in
            make.left.right.equalTo(nameField)
            make.top.equalTo(siteIconTitleLabel.snp.bottom).offset(SCRYFrom(8))
            make.height.equalTo(collectionView.snp.width)
                .multipliedBy(heightMultiplier)
                .offset(heightOffset)
            make.bottom.equalToSuperview().offset(SCRYFrom(-20))
        }
    }

    @objc private func close() {
        if navigationController?.presentingViewController != nil {
            navigationController?.dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    @objc private func doneBtnClick() {
        guard validateName(showLengthTip: false), !isCommitting else { return }
        let online = NetworkRequest.shared.networkable
        let plan = coordinator.makeCommitPlan(
            draft: draft,
            online: online,
            now: Int64(Date().timeIntervalSince1970)
        )
        guard plan.hasPendingFields else {
            close()
            return
        }

        if plan.includesTimezone {
            if online {
                showTimeZoneConfirmation()
            } else {
                showOfflineTimeZoneAlert()
            }
        } else {
            performCommit(online: online)
        }
    }

    private func showTimeZoneConfirmation() {
        let offset = draft.values.timezone?.displayOffset ?? ""
        let message = String(
            format: "site_update_time_zone_message".localizedString,
            offset
        )
        SRAlertView(
            title: "site_update_time_zone_title".localizedString,
            message: message,
            actions: [
                .cancelAction,
                SRAlertAction(
                    title: "site_update_time_zone_action".localizedString,
                    performsActionAfterDismiss: true,
                    actionHandler: { [weak self] _ in
                        self?.performCommit(online: true)
                    }
                )
            ]
        ).show()
    }

    private func showOfflineTimeZoneAlert() {
        SRAlertView(
            title: "site_you_are_offline".localizedString,
            message: "site_time_zone_offline_message".localizedString,
            actions: [
                SRAlertAction(
                    title: "site_got_it".localizedString,
                    performsActionAfterDismiss: true,
                    actionHandler: { [weak self] _ in
                        self?.performCommit(online: false)
                    }
                )
            ]
        ).show()
    }

    private func performCommit(online: Bool) {
        guard !isCommitting else { return }
        isCommitting = true
        let plan = coordinator.makeCommitPlan(
            draft: draft,
            online: online,
            now: Int64(Date().timeIntervalSince1970)
        )

        switch coordinator.persist(plan) {
        case .failure:
            isCommitting = false
            XWHUDManager.showErrorTipHUD("site_update_failed_toast".localizedString)

        case .success(let snapshot):
            siteDidChange?()
            if plan.includesTimezone {
                finishTimeZoneCommit(snapshot: snapshot, online: online)
            } else {
                finishOrdinaryCommit(snapshot: snapshot, online: online)
            }
        }
    }

    private func finishOrdinaryCommit(
        snapshot: SitePropsUpdateSnapshot?,
        online: Bool
    ) {
        finishEditing { [coordinator, siteDidChange] resultHost in
            guard online, let snapshot = snapshot else {
                Self.showOrdinaryUpdateToast(in: resultHost, success: false)
                return
            }
            Task { @MainActor in
                let success = await coordinator.submit(snapshot)
                siteDidChange?()
                Self.showOrdinaryUpdateToast(in: resultHost, success: success)
            }
        }
    }

    private static func showOrdinaryUpdateToast(in host: UIView, success: Bool) {
        ToastStatusView.show(
            in: host,
            message: success
                ? "site_updated_toast".localizedString
                : "site_update_failed_toast".localizedString,
            type: success ? .success : .failure,
            appearance: .siteUpdate
        )
    }

    private func finishTimeZoneCommit(
        snapshot: SitePropsUpdateSnapshot?,
        online: Bool
    ) {
        finishEditing { [coordinator, siteDidChange] _ in
            guard online, let snapshot = snapshot else { return }
            let statusView = SiteTimeZoneSyncStatusView()
            statusView.show()
            Task { @MainActor in
                let success = await coordinator.submit(snapshot)
                siteDidChange?()
                statusView.update(state: success ? .success : .failure)
            }
        }
    }

    private func finishEditing(completion: @escaping SiteResultHostCompletion) {
        finishEditingHandler(completion)
    }

    @objc private func nameFieldDidChange() {
        guard let text = nameField.text else { return }
        if text.count > 32 {
            nameField.text = String(text.prefix(32))
            validateName(showLengthTip: true)
        } else {
            validateName(showLengthTip: false)
        }
    }

    @discardableResult
    private func validateName(showLengthTip: Bool) -> Bool {
        let text = nameField.text ?? ""
        draft.values.siteName = text
        let isEmpty = text.isAllInputTextEmpty()
        let isTautonym = text != site.name && SiteData.isTautonym(siteName: text)
        if showLengthTip {
            nameTipLabel.text = "text_length_exceeded".localizedString
        } else if isTautonym {
            nameTipLabel.text = "name_already_exists".localizedString
        } else {
            nameTipLabel.text = nil
        }
        doneButton.isEnabled = !isEmpty && !isTautonym
        return doneButton.isEnabled
    }

    @objc private func selectTimeZone() {
        guard let controller = SiteTimeZoneSelectionViewController(onSelect: { [weak self] value in
            guard let self = self else { return }
            self.draft.values.timezone = value
            self.updateTimeZoneDisplay()
        }) else { return }
        preventModalStackDismissalForTimeZone()
        navigationController?.pushViewController(controller, animated: true)
    }

    private func preventModalStackDismissalForTimeZone() {
        guard let navigationController else { return }
        if modalDismissalStateBeforeTimeZone == nil {
            modalDismissalStateBeforeTimeZone = navigationController.isModalInPresentation
        }
        navigationController.isModalInPresentation = true
    }

    private func restoreModalStackDismissalAfterTimeZoneIfNeeded() {
        guard let previousState = modalDismissalStateBeforeTimeZone else { return }
        navigationController?.isModalInPresentation = previousState
        modalDismissalStateBeforeTimeZone = nil
    }

    private func updateTimeZoneDisplay() {
        guard let timeZoneValue = draft.values.timezone else {
            timeZoneNameLabel.text = "site_time_zone_not_configured".localizedString
            timeZoneOffsetLabel.text = nil
            localTimeLabel.isHidden = true
            localTimeLabel.snp.updateConstraints { make in
                make.height.equalTo(0)
            }
            siteIconTitleLabel.snp.updateConstraints { make in
                make.top.equalTo(localTimeLabel.snp.bottom).offset(SCRYFrom(12))
            }
            stopLocalTimeUpdates()
            return
        }

        timeZoneNameLabel.text = timeZoneValue.ianaId
        timeZoneOffsetLabel.text = timeZoneValue.displayOffset
        localTimeLabel.isHidden = false
        localTimeLabel.snp.updateConstraints { make in
            make.height.equalTo(SCRYFrom(20))
        }
        siteIconTitleLabel.snp.updateConstraints { make in
            make.top.equalTo(localTimeLabel.snp.bottom).offset(SCRYFrom(16))
        }
        refreshLocalTime()
    }

    private func updatePendingDisplay() {
        notSyncedButton.isHidden = site.pendingSitePropsMask.isEmpty
    }

    private func refreshLocalTime() {
        guard let timeZoneValue = draft.values.timezone else { return }
        let formattedTime = timeZoneValue.formattedLocalDate(at: Date())
        localTimeLabel.text = String(
            format: "site_local_time_format".localizedString,
            formattedTime
        )
    }

    private func startLocalTimeUpdates() {
        guard draft.values.timezone != nil, localTimeTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshLocalTime()
        }
        RunLoop.main.add(timer, forMode: .common)
        localTimeTimer = timer
    }

    private func stopLocalTimeUpdates() {
        localTimeTimer?.invalidate()
        localTimeTimer = nil
    }

    private func registerLifecycleNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func appDidEnterBackground() {
        stopLocalTimeUpdates()
    }

    @objc private func appWillEnterForeground() {
        guard viewIfLoaded?.window != nil else { return }
        refreshLocalTime()
        startLocalTimeUpdates()
    }

}

extension SiteEditViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return imageNames.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: "cell",
            for: indexPath
        ) as! ImageCollectionViewCell
        cell.imageView.image = UIImage(named: imageNames[indexPath.item])
        cell.layer.borderWidth = selectedImageIndex == indexPath.item ? 0.5 : 0
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard selectedImageIndex != indexPath.item else { return }
        let oldIndexPath = IndexPath(item: selectedImageIndex, section: 0)
        selectedImageIndex = indexPath.item
        draft.values.imageId = selectedImageIndex + 1
        CATransaction.setDisableActions(true)
        collectionView.reloadItems(at: [oldIndexPath, indexPath])
        CATransaction.commit()
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let width = floor(
            (collectionView.bounds.width - flowLayout.minimumInteritemSpacing * 3) / 4 * 100
        ) / 100
        return CGSize(width: width, height: width)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        view.endEditing(true)
    }
}

extension SiteEditViewController: UITextFieldDelegate {

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
