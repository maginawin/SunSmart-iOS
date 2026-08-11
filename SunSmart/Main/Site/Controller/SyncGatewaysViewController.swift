//
//  SyncGatewaysViewController.swift
//  SunSmart
//
//  Created by One on 2026/8/13.
//

import UIKit
import CoreBluetooth
import NordicSigMeshSDK
import SnapKit

enum SyncGatewaysFinishReason {
    case done
    case back
    case interactivePop
    case invalidContext
}
final class SyncGatewaysViewController: UIViewController {

    private let context: SyncGatewaysContext
    private let cloudBridge: SyncGatewaysCloudBridge
    private let canStartSync: (SyncGatewayRuntimeTarget) -> Bool
    private let scanSession: SyncGatewaysScanSession
    private let timeSyncCoordinator: GatewayTimeSyncCoordinator
    private var state: SyncGatewaysState
    private var stateAttemptIDByGatewayID: [String: UUID] = [:]
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var isFinished = false
    private var isInBackground = false
    private var didStartScan = false
    private var isShowingBluetoothAlert = false

    private let scrollView = UIScrollView()
    private let contentStackView = UIStackView()
    private let timeZoneCardView = SyncGatewaysTimeZoneCardView()
    private let onSiteAlertView = SyncGatewaysOnSiteAlertView()
    private let nearbyHeaderView = SyncGatewaysSectionHeaderView(
        titleKey: "site_sync_gateways_nearby_title",
        showsSearching: true
    )
    private let nearbyRowsStackView = UIStackView()
    private let nearbyEmptyView = SyncGatewaysMessageView()
    private let otherHeaderView = SyncGatewaysSectionHeaderView(
        titleKey: "site_sync_gateways_other_title",
        showsSearching: false
    )
    private let otherRowsStackView = UIStackView()
    private let attentionView = SyncGatewaysMessageView()
    private let bottomActionBar = SyncGatewaysBottomActionBar()

    init(
        context: SyncGatewaysContext,
        cloudBridge: SyncGatewaysCloudBridge,
        canStartSync: @escaping (SyncGatewayRuntimeTarget) -> Bool
    ) {
        self.context = context
        self.cloudBridge = cloudBridge
        self.canStartSync = canStartSync
        self.scanSession = SyncGatewaysScanSession(context: context)
        self.timeSyncCoordinator = GatewayTimeSyncCoordinator(
            pageSessionID: context.sessionID
        )
        self.state = SyncGatewaysState(
            targets: context.targets.map(\.descriptor)
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "site_sync_gateways_title".localizedString
        view.backgroundColor = SyncGatewaysCopy.pageBackgroundColor
        navigationController?.setNavigationBarBackgroundColor(color: .white)
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal),
            style: .done,
            target: self,
            action: #selector(backDidTap)
        )
        setupUI()
        bindRuntime()
        installLifecycleObservers()
        render(state)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        nearbyHeaderView.startSearchingAnimation()
        guard !didStartScan else { return }
        didStartScan = true
        scanSession.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard !isFinished, isMovingFromParent else { return }
        if let transitionCoordinator, transitionCoordinator.isInteractive {
            transitionCoordinator.notifyWhenInteractionChanges { [weak self] context in
                guard !context.isCancelled else { return }
                self?.finish(reason: .interactivePop)
            }
        } else {
            finish(reason: .back)
        }
    }

    deinit {
        removeLifecycleObservers()
    }

    private func setupUI() {
        bottomActionBar.onDone = { [weak self] in
            self?.doneDidTap()
        }
        view.addSubview(bottomActionBar)
        bottomActionBar.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
        }

        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
            make.bottom.equalTo(bottomActionBar.snp.top)
        }

        contentStackView.axis = .vertical
        contentStackView.spacing = SCRYFrom(16)
        scrollView.addSubview(contentStackView)
        contentStackView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(SCRYFrom(16))
            make.left.equalToSuperview().offset(SCRXFrom(16))
            make.right.equalToSuperview().offset(SCRXFrom(-16))
            make.bottom.equalToSuperview().offset(SCRYFrom(-20))
            make.width.equalTo(scrollView.snp.width).offset(SCRXFrom(-32))
        }

        [nearbyRowsStackView, otherRowsStackView].forEach { stack in
            stack.axis = .vertical
            stack.spacing = SCRYFrom(16)
        }

        nearbyEmptyView.update(
            text: SyncGatewaysCopy.nearbyEmpty,
            fontSize: 14
        )

        [
            timeZoneCardView,
            onSiteAlertView,
            nearbyHeaderView,
            nearbyRowsStackView,
            nearbyEmptyView,
            otherHeaderView,
            otherRowsStackView,
            attentionView
        ].forEach(contentStackView.addArrangedSubview)

        nearbyHeaderView.snp.makeConstraints { make in
            make.height.equalTo(SCRYFrom(24))
        }
        otherHeaderView.snp.makeConstraints { make in
            make.height.equalTo(SCRYFrom(24))
        }
    }

    private func bindRuntime() {
        scanSession.onAdvertisement = { [weak self] id, rssi in
            self?.mutateState { state in
                state.receiveAdvertisement(id: id, rssi: rssi)
            }
        }
        scanSession.onActiveElapsed = { [weak self] elapsed in
            self?.mutateState { state in
                state.advanceActiveScan(by: elapsed)
            }
        }
        scanSession.onAvailabilityFailure = { [weak self] _ in
            self?.showBluetoothRequiredAlertIfNeeded()
        }

        timeSyncCoordinator.onPersistedSuccess = { [cloudBridge] target in
            cloudBridge.recordDeviceSuccessAndEnqueue(target)
        }
        timeSyncCoordinator.onUISettlement = { [weak self] id, _, result in
            self?.handleSettlement(gatewayID: id, result: result)
        }
        timeSyncCoordinator.onAttemptEnded = { [weak self] in
            guard let self, !isFinished, !isInBackground else { return }
            scanSession.resume()
        }
        cloudBridge.onCloudState = { [weak self] id, cloudState in
            self?.mutateState { state in
                state.setCloudState(id: id, state: cloudState)
            }
        }
    }

    private func mutateState(
        _ mutation: (inout SyncGatewaysState) -> Void
    ) {
        guard !isFinished else { return }
        mutation(&state)
        render(state)
    }

    private func render(_ state: SyncGatewaysState) {
        timeZoneCardView.update(
            siteName: context.siteName,
            timeZone: context.targetTimeZone,
            progress: state.progress
        )

        replaceRows(
            in: nearbyRowsStackView,
            items: state.nearbyItems,
            state: state
        )
        replaceRows(
            in: otherRowsStackView,
            items: state.otherItems,
            state: state
        )

        nearbyEmptyView.isHidden = !state.nearbyItems.isEmpty
        attentionView.isHidden = state.attentionCount == 0
        if state.attentionCount > 0 {
            attentionView.update(text: SyncGatewaysCopy.attention(state.attentionCount))
        }
    }

    private func replaceRows(
        in stackView: UIStackView,
        items: [SyncGatewayItemState],
        state: SyncGatewaysState
    ) {
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        items.forEach { item in
            guard let action = state.action(for: item.id) else { return }
            let cell = SyncGatewayCell()
            cell.update(item: item, action: action)
            if action == .sync || action == .retry {
                cell.onAction = { [weak self] in
                    self?.startSync(gatewayID: item.id)
                }
            }
            stackView.addArrangedSubview(cell)
        }
    }

    private func startSync(gatewayID: String) {
        guard !isFinished,
              let target = context.targets.first(where: {
                  $0.descriptor.id == gatewayID
              }) else {
            return
        }
        guard canStartSync(target) else {
            finish(reason: .invalidContext)
            cloudBridge.refreshSiteSnapshotNow()
            navigationController?.popViewController(animated: true)
            return
        }
        guard let peripheral = scanSession.peripheral(for: gatewayID) else {
            return
        }

        var stateAttemptID: UUID?
        mutateState { state in
            stateAttemptID = state.beginSync(id: gatewayID)
        }
        guard let stateAttemptID else { return }
        stateAttemptIDByGatewayID[gatewayID] = stateAttemptID
        scanSession.pause()
        guard timeSyncCoordinator.synchronize(
            target: target,
            peripheral: peripheral,
            targetTimeZone: context.targetTimeZone
        ) != nil else {
            stateAttemptIDByGatewayID[gatewayID] = nil
            mutateState { state in
                state.finishSync(
                    id: gatewayID,
                    attemptID: stateAttemptID,
                    result: .failure
                )
            }
            scanSession.resume()
            return
        }
    }

    private func handleSettlement(
        gatewayID: String,
        result: Result<Void, GatewayTimeSyncError>
    ) {
        guard let attemptID = stateAttemptIDByGatewayID.removeValue(
            forKey: gatewayID
        ) else {
            return
        }
        let success: Bool
        switch result {
        case .success:
            success = true
        case .failure:
            success = false
        }
        let gatewayName = state.item(id: gatewayID).map(
            SyncGatewaysCopy.gatewayName
        ) ?? gatewayID
        mutateState { state in
            state.finishSync(
                id: gatewayID,
                attemptID: attemptID,
                result: success ? .success : .failure
            )
        }
        guard !isInBackground else { return }
        ToastStatusView.show(
            in: view,
            message: SyncGatewaysCopy.toast(
                success: success,
                gatewayName: gatewayName
            ),
            type: success ? .success : .failure,
            appearance: .siteUpdate,
            position: .bottom
        )
    }

    private func installLifecycleObservers() {
        let center = NotificationCenter.default
        lifecycleObservers.append(
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.applicationDidEnterBackground()
            }
        )
        lifecycleObservers.append(
            center.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.applicationWillEnterForeground()
            }
        )
    }

    private func removeLifecycleObservers() {
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
        lifecycleObservers.removeAll()
    }

    private func applicationDidEnterBackground() {
        guard !isFinished else { return }
        isInBackground = true
        scanSession.pause()
        timeSyncCoordinator.handleAppDidEnterBackground()
    }

    private func applicationWillEnterForeground() {
        guard !isFinished else { return }
        isInBackground = false
        scanSession.resume()
    }

    private func showBluetoothRequiredAlertIfNeeded() {
        guard !isFinished, !isShowingBluetoothAlert else { return }
        isShowingBluetoothAlert = true
        let alert = SRAlertView(
            title: String(
                format: "bluetooth_required_title".localizedString,
                appName
            ),
            message: "bluetooth_required_message".localizedString,
            actions: [
                SRAlertAction(
                    title: "settings".localizedString,
                    titleColor: RGB(61, 110, 246),
                    titleFont: FONTS(SCRYFrom(15)),
                    actionHandler: { [weak self] _ in
                        self?.isShowingBluetoothAlert = false
                        if let url = URL(string: "App-Prefs:root=Bluetooth") {
                            UIApplication.shared.open(url)
                        }
                    }
                ),
                SRAlertAction(
                    title: "close".localizedString,
                    titleColor: RGB(61, 110, 246),
                    titleFont: Font_Medium_Size(15),
                    actionHandler: { [weak self] _ in
                        self?.isShowingBluetoothAlert = false
                    }
                )
            ]
        )
        alert.show()
    }

    private func finish(reason: SyncGatewaysFinishReason) {
        guard !isFinished else { return }
        isFinished = true
        scanSession.finish()
        timeSyncCoordinator.finishPage()
        cloudBridge.finishBatchIfNeeded()
        nearbyHeaderView.stopSearchingAnimation()
        removeLifecycleObservers()
    }

    @objc private func backDidTap() {
        finish(reason: .back)
        navigationController?.popViewController(animated: true)
    }

    private func doneDidTap() {
        finish(reason: .done)
        navigationController?.popViewController(animated: true)
    }
}
