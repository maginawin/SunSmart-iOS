#if DEBUG
import UIKit

@MainActor
final class DebugCloudJSONExporter {
    private var isExporting = false

    static func canExport(_ permission: Permission) -> Bool {
        permission == .owner || permission == .editor
    }

    /// Matches MenuPopView's icon inset and font, with space for the full label.
    static func menuWidth(items: [MenuPopView.MenuItem], minimum: CGFloat) -> CGFloat {
        let font = UIFont.systemFont(ofSize: SCRXFrom(13), weight: .light)
        let textWidth = items.map { ($0.title as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return max(minimum, ceil(textWidth + SCRXFrom(35 + 8 + 12)))
    }

    func share(site: SiteData, space: SpaceData? = nil, from presenter: UIViewController) {
        guard !isExporting, presenter.viewIfLoaded?.window != nil,
              presenter.presentedViewController == nil else { return }
        guard Self.canExport(space?.permission ?? site.permission) else {
            XWHUDManager.showErrorTipHUD("no_permission".localizedString)
            return
        }
        isExporting = true
        XWHUDManager.showCustomHUD(withMessage: nil, view: presenter.view)
        _Concurrency.Task { @MainActor [weak presenter] in
            defer {
                self.isExporting = false
            }
            var file: URL?
            do {
                let snapshot = try Snapshot(site: site, space: space)
                let payload = try await snapshot.payload()
                try snapshot.validate()
                let scope = snapshot.scope, name = snapshot.name, date = snapshot.date
                file = try await withCheckedThrowingContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            DebugCloudJSONFile.cleanExpired()
                            let url = try DebugCloudJSONFile.write(payload: payload, scope: scope,
                                name: name, date: date)
                            continuation.resume(returning: url)
                        } catch { continuation.resume(throwing: error) }
                    }
                }
                try snapshot.validate()
                XWHUDManager.hide()
                guard let presenter, presenter.viewIfLoaded?.window != nil,
                      presenter.presentedViewController == nil, let file else {
                    if let file { DebugCloudJSONFile.remove(file) }
                    return
                }
                let activity = UIActivityViewController(activityItems: [file], applicationActivities: nil)
                if let popover = activity.popoverPresentationController {
                    if let button = presenter.navigationItem.rightBarButtonItem {
                        popover.barButtonItem = button
                    } else {
                        popover.sourceView = presenter.view
                        popover.sourceRect = CGRect(x: presenter.view.bounds.maxX - 24,
                            y: presenter.view.safeAreaInsets.top + 1, width: 1, height: 1)
                    }
                }
                activity.completionWithItemsHandler = { _, _, _, error in
                    DebugCloudJSONFile.remove(file)
                    if error != nil {
                        DispatchQueue.main.async {
                            XWHUDManager.showErrorTipHUD("debug_json_export_failed".localizedString)
                        }
                    }
                }
                presenter.present(activity, animated: true)
            } catch {
                if let file { DebugCloudJSONFile.remove(file) }
                XWHUDManager.hide()
                if presenter?.viewIfLoaded?.window != nil {
                    XWHUDManager.showErrorTipHUD((error as? ExportError)?.message
                        ?? "debug_json_export_failed".localizedString)
                }
            }
        }
    }

    enum ExportError: Error {
        case changed, unavailable(String)
        var message: String {
            switch self {
            case .changed: return "debug_json_export_changed".localizedString
            case .unavailable(let name):
                return String(format: "debug_json_export_unavailable".localizedString, name)
            }
        }
    }

    /// Owns detached model copies and rejects changes across asynchronous reads.
    @MainActor struct Snapshot {
        let site: SiteData
        let space: SpaceData?
        let spaces: [SpaceData]
        let siteCopy: SiteData
        let copies: [SpaceData]
        let revision: ConfigurationSnapshotRevision
        let memory: Data
        let date = Date()
        let scope: String
        let name: String
        let username: String

        init(site: SiteData, space: SpaceData?) throws {
            guard Self.allowed(site: site, space: space),
                  let revision = ConfigurationSnapshotRevision.current() else { throw ExportError.changed }
            self.site = site
            self.space = space
            spaces = space.map { [$0] } ?? site.spaces.filter {
                $0.siteId == site.id && DebugCloudJSONExporter.canExport($0.permission)
            }
            guard Set(spaces.map(\.id)).count == spaces.count else { throw ExportError.changed }
            self.revision = revision
            memory = try Self.memoryStamp(site: site, space: space)
            siteCopy = site.copy()
            siteCopy.localAddress = site.localAddress
            copies = spaces.map { $0.copy() }
            scope = space == nil ? "Site" : "Space"
            name = space?.name ?? site.name
            username = UserData.currentUserName
            try validate()
        }

        private static func allowed(site: SiteData, space: SpaceData?) -> Bool {
            site.state == .normal && (space == nil || (space?.siteId == site.id && space?.state == .normal))
                && DebugCloudJSONExporter.canExport(space?.permission ?? site.permission)
        }

        func validate() throws {
            guard Self.allowed(site: site, space: space), revision == ConfigurationSnapshotRevision.current(),
                  username == UserData.currentUserName,
                  memory == (try Self.memoryStamp(site: site, space: space)),
                  spaces.allSatisfy({ DebugCloudJSONExporter.canExport($0.permission)
                      && SpaceConfigurationSafety.canReadDebugSnapshot($0) }) else { throw ExportError.changed }
        }

        func payload() async throws -> [String: Any] {
            try validate()
            var values: [[String: Any]] = []
            for copy in copies {
                guard let value = await copy.export(purpose: .debugInspection) else {
                    throw ExportError.unavailable(copy.name)
                }
                values.append(value)
                try validate()
            }
            let api: NetowrkReqeustApi
            if let space {
                guard let value = values.first else { throw ExportError.unavailable(name) }
                api = .spaceUpload(siteId: site.id, spaceId: space.id, spaceData: value)
            } else {
                guard var value = await siteCopy.export(spaceIds: []) else { throw ExportError.unavailable(name) }
                value["spaces"] = values
                api = .siteUpload(siteData: value)
            }
            try validate()
            guard let parameters = api.parameters else { throw ExportError.unavailable(name) }
            return parameters
        }

        private static func memoryStamp(site: SiteData, space: SpaceData?) throws -> Data {
            let members = space.map { [$0] } ?? site.spaces
            let metadata: [[String: Any]] = try members.map { item in
                ["identity": String(describing: ObjectIdentifier(item)), "id": item.id,
                 "siteId": item.siteId, "meshUUID": item.meshUUID, "networkId": item.meshNetworkId,
                 "name": item.name, "permission": item.permission.rawValue, "state": item.state.rawValue,
                 "image": item.imageId, "source": item.sourceType.rawValue, "create": item.create,
                 "update": item.lastUpdate, "prefix": item.displayDeviceNamePrefix,
                 "cct": item.showCCTQuickButtons, "control": item.controlType.rawValue,
                 "blink": item.deviceBlinkMode.rawValue, "zonesFailed": item.triggerZonesLoadFailed,
                 "zones": try JSONSerialization.jsonObject(with: JSONEncoder().encode(item.triggerZones))]
            }
            return try JSONSerialization.data(withJSONObject: [
                "id": site.id, "meshUUID": site.meshUUID, "networkId": site.meshNetworkId,
                "name": site.name, "image": site.imageId, "type": site.type.rawValue,
                "permission": site.permission.rawValue, "state": site.state.rawValue,
                "source": site.sourceType.rawValue, "create": site.create, "update": site.lastUpdate,
                "timezone": site.timezone as Any? ?? NSNull(), "address": site.localAddress as Any? ?? NSNull(),
                "spaces": metadata
            ], options: .sortedKeys)
        }
    }
}
#endif
