import UIKit

final class SiteEditViewController: SiteFormViewController {
    typealias SiteResultHostCompletion = (UIView) -> Void
    typealias FinishEditingHandler = (@escaping SiteResultHostCompletion) -> Void

    private let site: SiteData
    private var draft: SitePropsEditDraft
    private let coordinator: SitePropsEditCoordinator
    private let finishEditingHandler: FinishEditingHandler
    private weak var confirmationAlert: SRAlertView?

    var siteDidChange: (() -> Void)?
    var timeZoneSyncDidFinish: ((SiteTimeZoneEditSyncOutcome) -> Void)?

    init(site: SiteData, draft: SitePropsEditDraft, coordinator: SitePropsEditCoordinator,
         finishEditingHandler: @escaping FinishEditingHandler) {
        self.site = site
        self.draft = draft
        self.coordinator = coordinator
        self.finishEditingHandler = finishEditingHandler
        let type = (try? SiteExtensionStore.load(site).data.siteType) ?? site.siteExtensionData.siteType ?? .standard
        super.init(formDraft: SiteFormDraft(values: draft.values, properties: draft.standardProperties, siteType: type),
                   editingSite: site)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        confirmationAlert?.dismiss(animation: false)
    }

    override func submitForm(properties: SiteStandardProperties) {
        guard contextIsCurrent, !isCommitting, confirmationAlert?.superview == nil else { return }
        draft.values = SitePropsValues(siteName: formDraft.siteName, imageId: formDraft.imageId, timezone: formDraft.timezone)
        draft.standardProperties = properties
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
                showTimeZoneConfirmation(timezone: plan.targetState.values.timezone)
            } else {
                showOfflineTimeZoneAlert()
            }
        } else {
            performCommit(online: online)
        }
    }

    private func showTimeZoneConfirmation(timezone: SiteTimeZoneValue?) {
        let offset = timezone?.displayOffset ?? ""
        let message = String(
            format: "site_update_time_zone_message".localizedString,
            offset
        )
        let alert = SRAlertView(
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
        )
        confirmationAlert = alert
        alert.show()
    }

    private func showOfflineTimeZoneAlert() {
        let alert = SRAlertView(
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
        )
        confirmationAlert = alert
        alert.show()
    }

    private func performCommit(online: Bool) {
        guard contextIsCurrent, !isCommitting, viewIfLoaded?.window != nil,
              navigationController?.topViewController === self,
              let stored = SiteData.load(siteId: site.id), stored.region == site.region,
              stored.create == site.create, stored.state == .normal,
              stored.permissionOperates.contains(.edit) else { return }
        isCommitting = true
        let plan = coordinator.makeCommitPlan(
            draft: draft,
            online: online,
            now: Int64(Date().timeIntervalSince1970)
        )

        guard plan.hasPendingFields else {
            isCommitting = false
            close()
            return
        }

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
        guard online else {
            finishEditing { _ in }
            return
        }

        let callback = timeZoneSyncDidFinish
        guard let snapshot else {
            let statusView = SiteTimeZoneSyncStatusView()
            let failedState = SiteTimeZoneSyncPresentationState.result(
                site: .savedSuccessfully,
                gateways: .notStarted
            )
            finishEditing { [statusView, callback] _ in
                statusView.update(state: failedState)
                statusView.show()
                callback?(.siteFailed)
            }
            return
        }

        guard snapshot.values.timezone != nil else {
            finishEditing { _ in }
            return
        }
        let statusView = SiteTimeZoneSyncStatusView()
        let gatewaySession = SiteGatewayCloudTimeZoneSessionCoordinator(
            syncCoordinator: SiteGatewayCloudTimeZoneSyncCoordinator(
                api: SiteGatewayCloudTimeZoneAPIClient(),
                timing: SiteGatewayCloudTimeZoneContinuousTiming()
            )
        )
        let editSyncCoordinator = SiteTimeZoneEditSyncCoordinator(
            siteID: site.id,
            submitter: coordinator,
            gatewaySession: gatewaySession,
            makeTargets: { [site] targetTimeZone in
                SiteGatewayLocalTimeZoneContextBuilder.make(
                    site: site,
                    targetTimeZone: targetTimeZone
                )
            }
        )
        finishEditing { [statusView, editSyncCoordinator, callback, siteDidChange] _ in
            statusView.update(state: .working(.savingSite))
            statusView.show()
            Task { @MainActor [statusView, editSyncCoordinator, callback, siteDidChange] in
                let outcome = await editSyncCoordinator.run(
                    snapshot: snapshot,
                    onUpdate: { state in
                        statusView.update(state: state)
                    }
                )
                guard let outcome else { return }
                siteDidChange?()
                callback?(outcome)
            }
        }
    }

    private func finishEditing(completion: @escaping SiteResultHostCompletion) {
        finishEditingHandler(completion)
    }

}
