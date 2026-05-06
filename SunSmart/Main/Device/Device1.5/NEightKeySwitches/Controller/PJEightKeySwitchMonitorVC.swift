//
//  PJEightKeySwitchMonitorVC.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

final class PJEightKeySwitchMonitorVC: UIViewController {

    var deleteSwitchAction: ((DeviceSwitchData) -> Void)?

    private let viewModel: PJEightKeySwitchMonitorViewModel

    private let headerView = PJEightKeySwitchMonitorHeaderView()
    private let panelView = PJEightKeySwitchMonitorPanelView()
    private let bottomView = PJEightKeySwitchMonitorStatusSetView()
    private var isRefreshing = false
    private var nextRefreshSimulationWillSucceed = true

    init(space: SpaceData, switchData: PJEightKeySwitchData) {
        viewModel = PJEightKeySwitchMonitorViewModel(space: space, switchData: switchData)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = viewModel.title
        view.backgroundColor = Background_Color
        setupNavigation()
        setupUI()
        bindActions()
        updateUI()
    }

    @objc private func backAction() {
        dismissLikeSystem()
    }

    @objc private func moreAction() {
        var items: [MenuPopView.MenuItem] = []
        if viewModel.space.deviceOperates.contains(.edit) {
            items.append(.init(icon: UIImage(named: "menu_edit"), title: "edit".localizedString, tapItemBack: { [weak self] _ in
                self?.pushEditor()
            }))
        }
        if viewModel.space.deviceOperates.contains(.delete) {
            items.append(.init(icon: UIImage(named: "menu_delete"), title: "delete".localizedString, tapItemBack: { [weak self] _ in
                self?.deleteCurrentSwitch()
            }))
        }
        items.append(.init(icon: UIImage(named: "menu_information"), title: "information".localizedString, tapItemBack: { _ in
           //information
        }))
        items.append(.init(icon: UIImage(named: "Identify_gateway"), title: "Identify", tapItemBack: {  _ in
           //Identify
        }))
        

        let touchCenterX = view.width - navigationRightItemMargin - 15
        let touchCenterY = view.safeAreaInsets.top - 10
        let windowPoint = view.convert(CGPoint(x: touchCenterX, y: touchCenterY), to: UIApplication.shared.keyWindow())
        MenuPopView.show(items: items, anchorPoint: windowPoint, menuWidth: SCRXFrom(114))
    }

    private func setupNavigation() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(backAction))
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "more_vertical")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(moreAction))
    }

    private func setupUI() {
        [headerView, panelView, bottomView].forEach {
            view.addSubview($0)
        }

        headerView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(SCRYFrom(14))
            make.left.right.equalToSuperview()
            make.height.equalTo(SCRYFrom(24))
        }

        panelView.snp.makeConstraints { make in
            make.top.equalTo(headerView.snp.bottom).offset(SCRYFrom(18))
            make.left.equalToSuperview().offset(SCRXFrom(60))
            make.right.equalToSuperview().offset(-SCRXFrom(60))
            make.height.equalTo(SCRYFrom(502))
        }

        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
        }
    }

    private func bindActions() {
        headerView.refreshAction = { [weak self] in
            self?.refreshMonitor()
        }

        panelView.dimmingLongPressAction = { [weak self] _ in
            self?.presentDimmingPopup()
        }
        panelView.autoLongPressAction = { [weak self] in
            self?.presentForcedAutoPopup()
        }
        panelView.disabledTapAction = {
            XWHUDManager.showTipHUD("neightkeyswitches_disabled_tip".localizedString, isLineFeed: true)
        }

        bottomView.enableChanged = { [weak self] isOn in
            guard let self else { return }
            self.viewModel.updateEnabled(isOn)
            self.viewModel.persist()
            NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
            self.updateUI()
        }

        bottomView.groupLinkAction = {
            XWHUDManager.showTipHUD("group", isLineFeed: false)
        }
    }

    private func updateUI() {
        let header = viewModel.headerState
        headerView.configure(state: .init(
            batteryText: header.batteryText,
            batteryIconSystemName: header.batteryIconSystemName,
            statusPrefixText: header.statusPrefixText,
            statusText: header.statusText,
            statusColor: header.statusColor,
            updatedText: header.updatedText
        ))

        panelView.configure(items: viewModel.keyItems, enabled: viewModel.settingsState.isEnabled)
        bottomView.configure(state: .init(
            groupNames: viewModel.settingsState.groupNames,
            isGroupLinked: viewModel.settingsState.isGroupLinked,
            isEnabled: viewModel.settingsState.isEnabled
        ))
    }

    private func refreshMonitor() {
        guard !isRefreshing else { return }
        isRefreshing = true

        let willSucceed = nextRefreshSimulationWillSucceed
        nextRefreshSimulationWillSucceed.toggle()

        let vc = PJEightKeySwitchRefreshAlertController()
        vc.cancelAction = { [weak self] in
            self?.isRefreshing = false
        }
        vc.retryAction = { [weak self, weak vc] in
            self?.scheduleRefreshSimulation(for: vc, willSucceed: true)
        }
        present(vc, animated: true) { [weak self, weak vc] in
            vc?.startWaiting()
            self?.scheduleRefreshSimulation(for: vc, willSucceed: willSucceed)
        }
    }

    private func scheduleRefreshSimulation(for controller: PJEightKeySwitchRefreshAlertController?, willSucceed: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self, weak controller] in
            guard let self, let controller, controller.presentingViewController != nil else { return }
            self.updateUI()
            self.isRefreshing = false
            if willSucceed {
                controller.showUpdated()
            } else {
                controller.showTimeout()
            }
        }
    }

    private func presentDimmingPopup() {
        let vc = PJEightKeySwitchDimmingPopupController()
        present(vc, animated: true)
    }

    private func presentForcedAutoPopup() {
        let vc = PJEightKeySwitchForcedAutoPopupController()
        present(vc, animated: true)
    }

    private func pushEditor() {
        let vc = PJPreAddEightKeySwitchesVC(space: viewModel.space, switchData: viewModel.switchData)
        vc.deleteSwitchAction = deleteSwitchAction
        present(NavigationViewController(rootViewController: vc), animated: true)
    }

    private func deleteCurrentSwitch() {
        SRAlertView(
            title: "notification".localizedString,
            message: "switchs_delete_message".localizedString,
            actions: [
                .cancelAction,
                SRAlertAction(title: "confirm".localizedString, style: .destructive, actionHandler: { [weak self] _ in
                    guard let self else { return }
                    self.dismiss(animated: true) {
                        self.deleteSwitchAction?(self.viewModel.switchData)
                    }
                })
            ]
        ).show()
    }
}
